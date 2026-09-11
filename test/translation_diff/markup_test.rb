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

  # What Google and DeepL do: html-escape whatever text they hand back, then what Response.build now undoes.
  def vendor_escaped(source)
    subject = passage(source)
    subject.segments.reject(&:empty?).each do |s|
      s.translation = TranslationDiff::Markup.decode_entities(CGI.escapeHTML(s.core))
    end
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
    assert_equal "IF A &lt; B THEN <b>STOP.</b>", translated("if a < b then <b>stop.</b>")
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
    assert_equal "\u00A9 \u2014 \u2026", TranslationDiff::Markup.decode_entities("&copy; &mdash; &hellip;")
    assert_equal "& < > \" ' \u00A0", TranslationDiff::Markup.decode_entities("&amp; &lt; &gt; &quot; &apos; &nbsp;")
    assert_equal "& & \u00A0 \u00A0", TranslationDiff::Markup.decode_entities("&#38; &#x26; &#160; &#xA0;")
  end

  # Sane rather than an exception, and sane here means untouched: what is not an entity is text, and stays text.
  def test_decoding_leaves_a_malformed_entity_exactly_as_it_arrived
    ["&notanentity;", "&#xZZ;", "&#;", "&#999999999;", "&Bogus9;", "AT&T", "a &gt b", "&"].each do |text|
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
    assert_round_trips("One &mdash; two &hellip; three. Fine.")
  end

  # The bargain, in a test: bytes are promised only while a segment is untranslated.
  def test_a_translated_sentence_renders_equivalent_markup_rather_than_equal_bytes
    assert_equal "A > B here. Fine.", echoed("A &gt; B here. Fine.")
    assert_equal "AT&amp;T is a company. Fine.", echoed("AT&T is a company. Fine.")
    assert_equal "Hard\u00A0space here. Fine.", echoed("Hard&nbsp;space here. Fine.")
  end

  # The whole HTML5 named set, not just the specials CGI knows: a spelled-out `&copy;` would display as text, not as ©.
  def test_a_named_entity_outside_cgis_table_is_translated_as_the_character_it_means
    assert_equal ["\u00A9 2026.", "Fine."], cores("&copy; 2026. Fine.")
    assert_equal "\u00A9 2026. Fine.", echoed("&copy; 2026. Fine.")
    assert_equal "One \u2014 two \u2026 three. Fine.", echoed("One &mdash; two &hellip; three. Fine.")
  end

  # A lone `&` is invalid XML and Ox raises on it, so nothing but a single well-formed entity is ever handed over.
  def test_a_lone_ampersand_never_reaches_the_entity_resolver
    assert_equal ["AT&T is a company.", "Fine."], cores("AT&T is a company. Fine.")
    assert_equal "AT&amp;T is a company. Fine.", echoed("AT&T is a company. Fine.")
    assert_equal "R&D; x", TranslationDiff::Markup.decode_entities("R&D; x")
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

  # -- a vendor's own escaping -----------------------------------------------

  # Reproduces the shipped bug: Google and DeepL html-escape every reply, apostrophes and quotes included.
  def test_a_vendor_that_escapes_apostrophes_and_quotes_round_trips_clean
    assert_equal "He didn't take the boat.", vendor_escaped("He didn't take the boat.")
    assert_equal %(She said, "We're not ready."), vendor_escaped(%(She said, "We're not ready."))
  end

  # An ampersand a vendor escaped is undone once, then re-escaped once at render -- never doubled either way.
  def test_a_vendor_escaped_ampersand_is_not_doubled
    assert_equal "5 &amp; 7 are important.", vendor_escaped("5 & 7 are important.")
  end

  # The notranslate span's own text is sent and returned like any other sentence, entity and all.
  def test_a_vendor_escaped_notranslate_span_keeps_its_ampersand_readable
    assert_equal %(<span class="notranslate">R&amp;D</span> Fine.),
                 vendor_escaped(%(<span class="notranslate">R&D</span> Fine.))
  end

  # One decode pass, never two: a reply already doubly-escaped loses only the level the wire itself added.
  def test_decoding_a_double_encoded_reply_removes_only_one_level
    assert_equal "&amp;", TranslationDiff::Markup.decode_entities("&amp;amp;")
  end
end
