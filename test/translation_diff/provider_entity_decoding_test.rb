require "test_helper"

# Round 2 of the entity-decoding fix: a provider's own `&lt;` must never reach the page as a bare, tag-forming `<`.
class ProviderEntityDecodingTest < ConfiguredTest
  # What a real vendor does: escape a literal `&` and a `<` that opens no tag; a genuine tag is left alone.
  def self.vendor_escape(text)
    text.gsub(/&|<(?!#{TranslationDiff::Markup::TAG_OPENER})/) { |match| match == "&" ? "&amp;" : "&lt;" }
  end

  # Mimics Google/DeepL: html-aware on the way in too, so an `&lt;` sent as safe HTML is read as the character
  # it means, not retranslated as four literal letters, before the reply is escaped the way a real vendor's is.
  class EscapingProvider < TranslationDiff::Provider
    def self.capabilities
      TranslationDiff::Capabilities.new(
        max_request_size: 1_000, max_batch_size: 10, max_text_size: nil,
        html: :format, notranslate: true, detects_language: false, reports_billing: false
      )
    end

    def translate(request)
      texts = request.texts.map { |text| ProviderEntityDecodingTest.vendor_escape(TranslationDiff::Markup.decode_entities(text)) }
      TranslationDiff::Translation::Response.build(request: request, texts: texts)
    end

    def cache_key = "escaping"
  end

  # A provider that ignores what it is sent and returns a fixed string -- for reproducing the injection directly.
  class FixedProvider < TranslationDiff::Provider
    def self.capabilities = EscapingProvider.capabilities

    def initialize(config, text:)
      super(config)
      @text = text
    end

    def translate(request)
      TranslationDiff::Translation::Response.build(request: request, texts: request.texts.map { @text })
    end

    def cache_key = "fixed"
  end

  def tags_in(html) = html.scan(%r{</?[A-Za-z][^>]*>})

  def translate(source, provider)
    TranslationDiff.translate(source, from: "ru", to: "en", provider: provider)
  end

  # The shipped hole: a provider's own `&lt;b attack` must never become a real, page-breaking `<b attack>` tag.
  def test_a_dangerous_tag_shaped_entity_never_forms_a_real_tag
    provider = FixedProvider.new(TranslationDiff::Configuration.new, text: "Value &lt;b attack here.")
    output = translate("<p>Value X here.</p>", provider)

    assert_includes output, "&lt;b attack"
    assert_equal ["<p>", "</p>"], tags_in(output)
  end

  # DeepL/Google's own reproduction case: `&lt;` and `&amp;` come back as entities -- not bare, not doubled.
  # `>` was never escaped by this gem, translated or not, so it stays literal; only `<` and `&` are at stake.
  def test_a_vendor_that_escapes_preserves_comparison_entities
    provider = EscapingProvider.new(TranslationDiff::Configuration.new)
    output = translate("<p>Сравните: 5 &lt; 7 &amp;&amp; 7 &gt; 5.</p>", provider)

    assert_equal "<p>Сравните: 5 &lt; 7 &amp;&amp; 7 > 5.</p>", output
  end

  # The apostrophe/quote corruption this branch already fixed must stay fixed alongside the new tag protection.
  def test_apostrophe_and_quote_corruption_stays_fixed
    provider = EscapingProvider.new(TranslationDiff::Configuration.new)

    assert_equal "<p>He didn't take the boat away.</p>", translate("<p>He didn't take the boat away.</p>", provider)
    assert_equal "<p>5 &amp; 7 are important.</p>", translate("<p>5 & 7 are important.</p>", provider)
  end

  # The property that would have caught this: a real article's tags, count and sequence, survive the round trip.
  ARTICLE = <<~HTML.chomp
    <article>
    <h1>Guide to Shell Quoting</h1>
    <p>Compare: 5 &lt; 7 and check the &amp; operator carefully.</p>
    <p>Run <code>jq &#39;.meters&#39;</code> to extract the field.</p>
    <p><a href="/x?a=1&amp;b=2" title="A &amp; B">Read more</a> about the topic.</p>
    <p>The vendor <span class="notranslate">TrustedCo</span> provided this data.</p>
    </article>
  HTML

  def test_a_real_articles_tag_count_and_sequence_survive_a_round_trip
    provider = EscapingProvider.new(TranslationDiff::Configuration.new)
    output = translate(ARTICLE, provider)

    assert_equal tags_in(ARTICLE), tags_in(output)
  end
end
