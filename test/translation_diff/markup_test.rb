require "test_helper"

class MarkupTest < Minitest::Test
  def passage(source)
    TranslationDiff::Passage.new(source, segmenter: TranslationDiff::Segmenters::Pragmatic.new)
  end

  def cores(source) = passage(source).segments.reject(&:empty?).map(&:core)

  def translated(source)
    subject = passage(source)
    subject.segments.reject(&:empty?).each { |s| s.translation = s.core.upcase }
    subject.render
  end

  # What the :null provider does: every sentence comes back as the text it was sent, so only markup handling shows.
  def echoed(source)
    subject = passage(source)
    subject.segments.reject(&:empty?).each { |s| s.translation = s.core }
    subject.render
  end

  def assert_round_trips(source)
    assert_equal source, passage(source).render, "render must return the source byte for byte"
  end

  # -- entities ------------------------------------------------------------

  # What reaches a provider is text, so it gets the character, not the entity.
  def test_an_entity_is_decoded_before_translation
    assert_equal ["Salt & pepper.", "Fine."], cores("Salt &amp; pepper. Fine.")
  end

  def test_a_non_breaking_space_is_decoded
    assert_equal ["Hard\u00A0space here.", "Fine."], cores("Hard&nbsp;space here. Fine.")
  end

  # The document keeps the entities it arrived with.
  def test_entities_are_restored_on_render
    assert_equal "SALT &amp; PEPPER. FINE.", translated("Salt &amp; pepper. Fine.")
  end

  def test_an_untranslated_document_with_entities_round_trips
    source = "Salt &amp; pepper. Hard&nbsp;space. Fine."

    assert_equal source, passage(source).render
  end

  # -- the bare < ----------------------------------------------------------

  def test_a_bare_less_than_stays_in_the_sentence
    assert_equal ["if a < b then stop.", "Fine."], cores("if a < b then stop. Fine.")
  end

  def test_bare_angles_on_both_sides_stay_prose
    assert_equal ["5 < 6 and 7 > 6.", "True."], cores("5 < 6 and 7 > 6. True.")
  end

  def test_a_bare_less_than_survives_rendering_untranslated
    source = "if a < b then stop. Fine."

    assert_equal source, passage(source).render
  end

  # The distinction that makes this hard: a real tag must still be a tag when
  # the same string also contains a bare <.
  def test_a_real_tag_beside_a_bare_less_than_is_still_markup
    assert_equal ["if a < b then", "stop."], cores("if a < b then <b>stop.</b>")
    assert_equal "IF A < B THEN <b>STOP.</b>", translated("if a < b then <b>stop.</b>")
  end

  def test_a_less_than_immediately_before_a_letter_is_a_tag
    assert_equal ["Bold", "text."], cores("<b>Bold</b> text.")
  end

  # -- the escape and its inverse ------------------------------------------

  # Every mixture of real tags, bare angles and already-escaped angles the
  # workaround has to survive; each must come back exactly as it went in.
  MIXED = [
    "if a < b then stop.",
    "5 < 6 and 7 > 6.",
    "<b>Bold</b> and a < b.",
    "a < b and <i>c</i> < d.",
    "&lt; is already an entity.",
    "&amp;lt; is an entity for an entity.",
    "a < b, &lt; c, &amp;lt; d, <b>e</b>.",
    "<!-- a < b --> Visible.",
    %(<a title="a &lt; b">Link.</a> After.),
    "trailing angle <",
    "<",
    "<3 is not a tag.",
    ""
  ].freeze

  def test_restoring_undoes_escaping
    MIXED.each do |source|
      escaped = TranslationDiff::Markup.escape_bare_angles(source)

      assert_equal source, TranslationDiff::Markup.restore_bare_angles(escaped),
                   "escape and restore must be a matched pair for #{source.inspect}"
    end
  end

  def test_escaping_leaves_no_bare_angle_for_ox_to_swallow
    MIXED.each do |source|
      escaped = TranslationDiff::Markup.escape_bare_angles(source)

      refute_match(%r{<(?![A-Za-z!?]|/[A-Za-z])}, escaped, "#{escaped.inspect} still holds a bare <")
    end
  end

  def test_every_mixed_input_round_trips_through_a_passage
    MIXED.each { |source| assert_round_trips(source) }
  end

  # -- decoding and encoding -----------------------------------------------

  # Every entity is decoded, not the two that were measured: an `&` we leave behind is an `&` encoding corrupts.
  def test_decoding_resolves_named_and_numeric_entities
    assert_equal "& < > \" ' \u00A0", TranslationDiff::Markup.decode_entities("&amp; &lt; &gt; &quot; &apos; &nbsp;")
    assert_equal "& & \u00A0 \u00A0", TranslationDiff::Markup.decode_entities("&#38; &#x26; &#160; &#xA0;")
  end

  # Sane rather than an exception, and sane here means untouched: what is not an entity is text, and stays text.
  def test_decoding_leaves_a_malformed_entity_exactly_as_it_arrived
    ["&notanentity;", "&#xZZ;", "&#;", "&#999999999;", "&hellip;", "AT&T", "a &gt b", "&"].each do |text|
      assert_equal text, TranslationDiff::Markup.decode_entities(text)
    end
  end

  # A numeric reference can name a surrogate; decoding one would hand back invalid UTF-8 for a later regexp to raise on.
  def test_decoding_refuses_a_reference_that_would_not_be_valid_utf8
    decoded = TranslationDiff::Markup.decode_entities("&#xD800;")

    assert_equal "&#xD800;", decoded
    assert_predicate decoded, :valid_encoding?
  end

  # Only the two characters that are unsafe in HTML text; a decoded character stays the character it decoded to.
  def test_encoding_touches_only_the_ampersand_and_the_opening_angle
    assert_equal "&amp; &lt;b> > \" ' \u00A0", TranslationDiff::Markup.encode_entities("& <b> > \" ' \u00A0")
  end

  # -- entities we never decoded -------------------------------------------

  # Every one of these came back with its `&` escaped a second time before the decode was made whole.
  def test_an_entity_outside_the_decoded_set_is_not_escaped_again
    assert_round_trips("A &gt; B here. Fine.")
    assert_round_trips("AT&T is a company. Fine.")
    assert_round_trips("&copy; 2026. Fine.")
    assert_round_trips("&notanentity; here. Fine.")
  end

  # The bargain, in a test: bytes are promised only while a segment is untranslated.
  def test_a_translated_sentence_renders_equivalent_markup_rather_than_equal_bytes
    assert_equal "A > B here. Fine.", echoed("A &gt; B here. Fine.")
    assert_equal "AT&amp;T is a company. Fine.", echoed("AT&T is a company. Fine.")
    assert_equal "Hard\u00A0space here. Fine.", echoed("Hard&nbsp;space here. Fine.")
  end

  # CGI's table is the HTML specials and the numeric forms, so a `&copy;` that is translated is spelled, not resolved.
  def test_a_named_entity_cgi_cannot_decode_survives_translation_as_text
    assert_equal "&amp;copy; 2026. Fine.", echoed("&copy; 2026. Fine.")
  end

  # -- what still has to hold ----------------------------------------------

  # A notranslate element is prose that contains real tags; encoding must not eat them.
  def test_a_notranslate_element_keeps_its_tags_through_a_render
    assert_round_trips(%(<span class="notranslate">Bold Mountain</span> is a good place.))
  end

  # Passed through untouched means untouched: an `&` inside a protected element is not ours to respell.
  def test_a_notranslate_element_keeps_its_ampersands_through_a_render
    assert_round_trips(%(<span class="notranslate">R&D & more</span> Fine.))
  end

  def test_an_entity_inside_markup_is_left_for_the_browser
    assert_round_trips(%(<a href="/x?a=1&b=2" title='q'>Link text.</a> After.))
    assert_round_trips("Before.<![CDATA[raw & unparsed]]>After.")
  end
end
