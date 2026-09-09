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

  # String literals are mutable in this project -- the magic comment was
  # removed everywhere -- so a segment must not alias the string it was given.
  def test_mutating_the_source_afterwards_does_not_change_the_segment
    source = +"  One.  "
    segment = TranslationDiff::Segment.new(source)
    source << "trailing junk"

    assert_equal "  One.  ", segment.source
    assert_equal "One.", segment.core
    assert_equal "  One.  ", segment.render
  end

  def test_a_segment_of_only_a_non_breaking_space_is_empty
    segment = TranslationDiff::Segment.new(" ")

    assert_predicate segment, :empty?
    assert_equal " ", segment.render
  end

  def test_a_non_breaking_space_around_a_sentence_is_padding
    segment = TranslationDiff::Segment.new(" One. ")
    segment.translation = "Один."

    assert_equal "One.", segment.core
    assert_equal " Один. ", segment.render
  end
end
