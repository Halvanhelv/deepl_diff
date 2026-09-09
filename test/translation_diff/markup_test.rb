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

  def test_decoding_resolves_only_the_entities_encoding_can_put_back
    assert_equal "& \u00A0 < &gt;", TranslationDiff::Markup.decode_entities("&amp; &nbsp; &lt; &gt;")
  end

  # < is left alone on purpose: restoring a bare angle is the escape's job, and
  # a real tag inside a protected element must stay a real tag.
  def test_encoding_puts_back_the_characters_decoding_took
    assert_equal "&amp; &nbsp; <b>", TranslationDiff::Markup.encode_entities("& \u00A0 <b>")
  end

  # -- what still has to hold ----------------------------------------------

  # A notranslate element is prose that contains real tags; encoding must not eat them.
  def test_a_notranslate_element_keeps_its_tags_through_a_render
    assert_round_trips(%(<span class="notranslate">Bold Mountain</span> is a good place.))
  end

  def test_an_entity_inside_markup_is_left_for_the_browser
    assert_round_trips(%(<a href="/x?a=1&b=2" title='q'>Link text.</a> After.))
    assert_round_trips("Before.<![CDATA[raw & unparsed]]>After.")
  end
end
