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
    ["Ի՞նչ ես մտածում: Ոչինչ:", "hy"],
    # Single newlines (shadowed) and a blank-line paragraph break (not
    # shadowed), together, so the invariant is exercised against both paths.
    ["The cat sat on the mat\nand looked at the moon. It was content.\n\n" \
     "A new paragraph starts here.", "en"],
    ["これは父の\n家です。それはペンです。", "ja"]
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

  # pragmatic_segmenter treats essentially any single newline as a sentence
  # boundary candidate, independent of punctuation -- confirmed on ordinary,
  # punctuation-free, line-wrapped prose, including with whitespace on both
  # sides of the newline (not just a newline glued to non-whitespace). A
  # false split is the harmful kind of error this whole gem exists to avoid,
  # and it is common: HTML text nodes routinely carry incidental newlines
  # from source formatting. Shadowing single newlines before segmenting
  # fixes this while leaving the original text -- newline included -- in
  # the output.
  def test_a_single_newline_with_no_punctuation_does_not_split_the_sentence
    text = "Some text \n continues here without any punctuation at the break"
    assert_equal [0], @segmenter.split_offsets(text)
  end

  def test_a_single_newline_between_two_real_sentences_is_preserved_as_a_boundary_gap
    text = "This is a sentence\ncut off by a line wrap. A second sentence follows."
    offsets = @segmenter.split_offsets(text, language: "en")

    assert_equal [0, "This is a sentence\ncut off by a line wrap. ".length], offsets
  end

  # A blank-line run is a real paragraph break, not incidental formatting,
  # and shadowing deliberately leaves it alone -- pragmatic_segmenter already
  # handles it correctly (also covered by the reconstruction invariant above,
  # and by TokenizerTest's own blank-line case).
  def test_a_blank_line_paragraph_break_still_splits
    text = "Первое предложение.\n\nВторое предложение."
    offsets = @segmenter.split_offsets(text, language: "ru")

    assert_equal [0, "Первое предложение.\n\n".length], offsets
  end

  # Shadowing fixes the real trigger reported in the previous round: this no
  # longer raises, and the newline survives in the output exactly as it
  # appeared in the source.
  def test_the_japanese_newline_after_a_common_particle_now_segments_instead_of_raising
    text = "これは父の\n家です。それはペンです。"
    offsets = @segmenter.split_offsets(text, language: "ja")

    assert_equal [0, "これは父の\n家です。".length], offsets
  end

  # A genuine trigger for the raise that survives shadowing, since it has
  # nothing to do with newlines: pragmatic_segmenter's cleaner unconditionally
  # deletes a specific inline-formatting artefact
  # (lib/pragmatic_segmenter/cleaner/rules.rb, InlineFormattingRule) wherever
  # it appears, in every language. Shadowing narrows the raise's surface; it
  # does not close it, and this proves the guard still fires on real
  # `pragmatic_segmenter` behaviour rather than a contrived double.
  def test_raises_when_a_returned_sentence_cannot_be_located_in_the_source
    text = "This is a sentence{b^>3<b^} with markup noise. Second sentence follows now."

    error = assert_raises(TranslationDiff::Segmenters::Pragmatic::Error) do
      @segmenter.split_offsets(text, language: "en")
    end

    assert_includes error.message, "This is a sentence with markup noise.".inspect
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
