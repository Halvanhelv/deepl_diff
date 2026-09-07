# frozen_string_literal: true

require "test_helper"

class PragmaticSegmenterTest < Minitest::Test
  RECONSTRUCTION_SAMPLES = [
    ["", nil],
    ["   ", nil],
    ["No terminator here at all", nil],
    ["Hello there. Goodbye now.", "en"],
    ["Смеркалось. Ворчало. Кричало.", "ru"],
    ["Набор «Солнечная механика» от 4М — это 6 экспериментов.\n\n" \
     "Юному изобретателю предстоит воочию посмотреть на чудеса.", "ru"],
    ["見て。すごい！次はどうなる？", "ja"],
    ["Проф. Иванов пришёл домой. Было поздно.", "ru"],
    ["سؤال وجواب: ماذا حدث؟ طرح الكثير من التساؤلات.", "ar"],
    ["Ի՞նչ ես մտածում: Ոչինչ:", "hy"]
  ].freeze

  def setup
    @segmenter = TranslationDiff::Segmenters::Pragmatic.new
  end

  def test_reconstruction_invariant_holds_for_a_variety_of_inputs_and_languages
    RECONSTRUCTION_SAMPLES.each { |text, language| assert_reconstructs(text, language) }
  end

  def test_empty_string_yields_only_the_starting_offset
    assert_equal [0], @segmenter.split_offsets("")
  end

  def test_whitespace_only_string_yields_only_the_starting_offset
    assert_equal [0], @segmenter.split_offsets("   \n\t")
  end

  def test_string_with_no_terminator_at_all_is_not_split
    assert_equal [0], @segmenter.split_offsets("no terminator here at all")
  end

  def test_a_single_sentence_is_not_split
    assert_equal [0], @segmenter.split_offsets("Ends with a stop.")
  end

  def test_ordinary_sentence_boundary_splits
    text = "Hello there. Goodbye now."
    assert_equal [0, "Hello there. ".length], @segmenter.split_offsets(text)
  end

  def test_cjk_terminators_split_without_a_language_hint
    text = "見て。すごい！"
    assert_equal [0, "見て。".length], @segmenter.split_offsets(text)
  end

  # This is the trap the brief calls out by name: without a language,
  # pragmatic_segmenter falls back to English rules, and English rules read
  # "Проф." as a complete sentence on its own.
  def test_without_a_language_russian_abbreviations_are_mis_segmented
    text = "Проф. Иванов пришёл домой. Было поздно."
    offsets = @segmenter.split_offsets(text)

    assert_equal [0, "Проф. ".length, "Проф. Иванов пришёл домой. ".length], offsets
  end

  # The same text, with the language supplied, segments correctly -- proving
  # the language argument is actually threaded through to pragmatic_segmenter
  # rather than merely accepted and ignored.
  def test_with_the_language_russian_abbreviations_are_respected
    text = "Проф. Иванов пришёл домой. Было поздно."
    offsets = @segmenter.split_offsets(text, language: "ru")

    assert_equal [0, "Проф. Иванов пришёл домой. ".length], offsets
  end

  def test_blank_lines_between_sentences_are_attached_to_the_first_sentence
    text = "Набор «Солнечная механика» от 4М — это 6 экспериментов.\n\n" \
           "Юному изобретателю предстоит воочию посмотреть на чудеса."
    offsets = @segmenter.split_offsets(text, language: "ru")

    assert_equal [0, "Набор «Солнечная механика» от 4М — это 6 экспериментов.\n\n".length], offsets
  end

  # See TranslationDiff::Segmenters::Pragmatic for why this must raise rather
  # than guess: a silent, wrong offset would corrupt the document it feeds
  # back into. This is not a hypothetical -- pragmatic_segmenter's Japanese
  # cleaner deletes a "\n" that follows "の" (a very common particle, its
  # PDF-line-wrap heuristic), so the sentence it hands back no longer appears
  # verbatim in the source once there is a second sentence to search past.
  def test_raises_when_a_returned_sentence_cannot_be_located_in_the_source
    text = "これは父の\n家です。それはペンです。"

    error = assert_raises(TranslationDiff::Segmenters::Pragmatic::Error) do
      @segmenter.split_offsets(text, language: "ja")
    end

    assert_includes error.message, "これは父の家です。".inspect
    assert_includes error.message, text.inspect
  end

  private

  def assert_reconstructs(text, language)
    offsets = @segmenter.split_offsets(text, language: language)

    assert_valid_offsets(text, offsets)
    assert_equal text, reconstruct(text, offsets), "reconstruction failed for #{text.inspect}"
  end

  def assert_valid_offsets(text, offsets)
    assert_equal 0, offsets.first, "first offset for #{text.inspect}"
    assert_equal offsets.sort.uniq, offsets, "offsets not sorted/unique for #{text.inspect}"
  end

  def reconstruct(text, offsets)
    offsets.each_cons(2).map { |a, b| text[a...b] }.join + text[offsets.last..]
  end
end
