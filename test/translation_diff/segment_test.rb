require "test_helper"

class SegmentTest < Minitest::Test
  def test_core_is_the_sentence_without_its_padding
    assert_equal "It was getting dark.", TranslationDiff::Segment.new("  It was getting dark.  ").core
  end

  def test_source_is_kept_exactly
    assert_equal "  It was getting dark.  ", TranslationDiff::Segment.new("  It was getting dark.  ").source
  end

  def test_render_puts_the_translation_back_inside_the_original_padding
    segment = TranslationDiff::Segment.new("  It was getting dark.  ")
    segment.translation = "Смеркалось."

    assert_equal "  Смеркалось.  ", segment.render
  end

  # The padding is whatever was there, not a normalised guess at it.
  def test_padding_is_reproduced_character_for_character
    segment = TranslationDiff::Segment.new("\n\t One. \n")
    segment.translation = "Один."

    assert_equal "\n\t Один. \n", segment.render
  end

  def test_an_untranslated_segment_renders_its_source
    assert_equal "  One.  ", TranslationDiff::Segment.new("  One.  ").render
  end

  def test_translated_reports_whether_a_translation_was_set
    segment = TranslationDiff::Segment.new("One.")

    refute_predicate segment, :translated?
    segment.translation = "Один."
    assert_predicate segment, :translated?
  end

  # A run of whitespace between two sentences is a segment with nothing to
  # translate. It must render unchanged and never reach a provider.
  def test_a_segment_of_only_whitespace_is_empty
    segment = TranslationDiff::Segment.new("   \n ")

    assert_predicate segment, :empty?
    assert_equal "   \n ", segment.render
  end

  def test_a_segment_with_words_is_not_empty
    refute_predicate TranslationDiff::Segment.new(" One. "), :empty?
  end

  def test_an_empty_source_is_empty
    assert_predicate TranslationDiff::Segment.new(""), :empty?
  end
end
