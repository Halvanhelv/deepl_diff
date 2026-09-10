require "test_helper"

class PassageTest < Minitest::Test
  def passage(source)
    TranslationDiff::Passage.new(source, segmenter: TranslationDiff::Segmenters::Pragmatic.new)
  end

  # What a provider would be asked to translate, in order.
  def cores(source) = passage(source).segments.reject(&:empty?).map(&:core)

  def assert_round_trips(source)
    assert_equal source, passage(source).render, "render must return the source byte for byte"
  end

  # -- byte-exact reconstruction ------------------------------------------

  # rubocop:disable-next Metrics/MethodLength
  def test_every_corpus_input_round_trips_untranslated
    [
      "Hello there.",
      "<b>Bold</b> text here. Second sentence.",
      %(<a href="/x?a=1&b=2" title='q'>Link text.</a> After.),
      "One line.<br>Two lines.",
      "<p>First para.<p>Second para.",
      "<B>Bold</B> text.",
      "аль<span>бра</span>кил<script>js</script><style>b</style>",
      %(Hey!<br />Look!<?xml:namespace ns="urn:office" ?>),
      "<!-- internal note --> Visible text here.",
      "<!DOCTYPE html><p>Body text.</p>",
      "Before.<![CDATA[raw & unparsed]]>After.",
      "<font size='3'>Смеркалось.<br></font>",
      "  Padded sentence.  ",
      "Первое предложение.\n\nВторое предложение.",
      ""
    ].each { |source| assert_round_trips(source) }
  end

  # -- what counts as prose ----------------------------------------------

  def test_text_around_markup_is_prose
    assert_equal ["Bold", "text here.", "Second sentence."],
                 cores("<b>Bold</b> text here. Second sentence.")
  end

  def test_script_and_style_contents_are_not_prose
    assert_equal %w[аль бра кил], cores("аль<span>бра</span>кил<script>js</script><style>b</style>")
  end

  def test_a_comment_is_not_prose
    assert_equal ["Visible text here."], cores("<!-- internal note --> Visible text here.")
  end

  def test_a_doctype_is_not_prose
    assert_equal ["Body text."], cores("<!DOCTYPE html><p>Body text.</p>")
  end

  def test_a_processing_instruction_is_not_prose
    assert_equal %w[Hey! Look!], cores(%(Hey!<br />Look!<?xml:namespace ns="urn:office" ?>))
  end

  def test_attribute_values_are_not_prose
    assert_equal ["Link text.", "After."], cores(%(<a href="/x" title="Do not translate me">Link text.</a> After.))
  end

  # -- notranslate, which is prose ON PURPOSE ------------------------------

  # The provider honours class="notranslate" itself, under the HTML mode all
  # six providers send. Holding the span back as markup would deprive it of
  # the protection it exists to request.
  def test_a_notranslate_span_reaches_the_provider_with_its_tags
    source = %(<span class="notranslate">Bold Mountain</span> is a good place.)

    assert_equal [%(<span class="notranslate">Bold Mountain</span> is a good place.)], cores(source)
  end

  # Ox lowercases element names but not attribute names, and HTML attribute names are case-insensitive.
  def test_an_uppercase_class_attribute_still_protects
    source = %(<span CLASS="notranslate">Bold Mountain</span> is a good place.)

    assert_equal [source], cores(source)
  end

  # Class token values are case-sensitive in HTML and providers look for the lowercase word, so this asks for nothing.
  def test_an_uppercase_notranslate_value_does_not_protect
    assert_equal ["Bold Mountain", "is a good place."],
                 cores(%(<span class="NOTRANSLATE">Bold Mountain</span> is a good place.))
  end

  def test_a_notranslate_span_nested_in_another_is_one_unit
    source = "<span class='notranslate'>foo<span class='notranslate'>bar</span>baz</span>"

    assert_equal [source], cores(source)
  end

  def test_a_notranslate_span_inside_an_ordinary_span_keeps_the_outer_span_as_markup
    source = "<span><span class='notranslate'>foo<span>bar<br></span>baz</span></span>"

    assert_equal ["<span class='notranslate'>foo<span>bar<br></span>baz</span>"], cores(source)
  end

  # Protection beats opacity: the caller asked for this subtree to be passed through, script and all.
  def test_a_script_inside_a_notranslate_element_stays_inside_the_protected_unit
    source = %(<span class="notranslate"><script>alert(1)</script></span>)

    assert_equal [source], cores(source)
  end

  # -- sentence boundaries -------------------------------------------------

  def test_prose_is_cut_into_sentences
    assert_equal ["! Киловольт.", "Смеркалось.", "Ворчало.", "Кричало."],
                 cores("! Киловольт. <span>Смеркалось.    Ворчало. Кричало.</span>")
  end

  def test_a_blank_line_separates_sentences
    assert_equal ["Первое предложение.", "Второе предложение."],
                 cores("Первое предложение.\n\nВторое предложение.")
  end

  # A lone newline is not a sentence boundary -- this was a real regression.
  def test_a_single_newline_does_not_split_a_sentence
    assert_equal ["test\nphrase"], cores("test\nphrase")
  end

  def test_markup_holding_nothing_but_a_line_break_offers_nothing_to_translate
    assert_empty cores("<div>\n</div>")
    assert_round_trips("<div>\n</div>")
  end

  # -- translation and rendering -------------------------------------------

  def test_translating_every_segment_rebuilds_the_document
    subject = passage("<b>Bold</b> text here. Second sentence.")
    subject.segments.reject(&:empty?).each { |s| s.translation = s.core.upcase }

    assert_equal "<b>BOLD</b> TEXT HERE. SECOND SENTENCE.", subject.render
  end

  def test_padding_between_sentences_survives_translation
    subject = passage("  One.   Two.  ")
    subject.segments.reject(&:empty?).each { |s| s.translation = s.core.upcase }

    assert_equal "  ONE.   TWO.  ", subject.render
  end

  def test_an_untranslated_segment_renders_its_source
    subject = passage("One. Two.")
    subject.segments.reject(&:empty?).first.translation = "ОДИН."

    assert_equal "ОДИН. Two.", subject.render
  end
end
