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
    # Multiple blank lines: more than one blank line in a single gap, and
    # more than one such gap in the same text. Untouched by shadowing --
    # SINGLE_NEWLINE only matches a "\n" with no adjoining "\n".
    ["First paragraph.\n\n\nSecond paragraph.\n\n\n\nThird paragraph.", "en"],
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

  # H1 (fix round 2): pragmatic_segmenter's cleaner rewrites the sentence it
  # hands back in ways shadowing does not touch -- collapsing runs of three
  # or more spaces, respacing "Ph.D." into "Ph. D.", deleting a formatting
  # artefact outright. None of these are rare (an English sentence naming a
  # degree, or HTML indented with more than two spaces, hits one of them
  # routinely), and none of them may abort translation any more: recovery
  # stops at the first sentence it cannot verify and the remainder of the
  # text stands as one final unit -- a coarsening, not a failure. Each case
  # below is a real, reproduced trigger, not a hypothetical.
  def test_ph_d_no_longer_aborts_and_the_original_text_is_untouched
    text = "He has a Ph.D. in physics. It took years."
    assert_equal [0], @segmenter.split_offsets(text, language: "en")
  end

  def test_a_run_of_three_or_more_spaces_no_longer_aborts
    text = "A   b. Next one."
    assert_equal [0], @segmenter.split_offsets(text, language: "en")
  end

  def test_indented_html_with_a_two_space_indent_no_longer_aborts
    text = "<p>Some text\n    continues here. Next.</p>"
    assert_equal [0], @segmenter.split_offsets(text, language: "en")
  end

  def test_a_newline_plus_a_two_space_indent_no_longer_aborts
    text = "Some text\n  continues here. Next."
    assert_equal [0], @segmenter.split_offsets(text, language: "en")
  end

  # The inline-formatting artefact pragmatic_segmenter deletes outright
  # (lib/pragmatic_segmenter/cleaner/rules.rb, InlineFormattingRule) is what
  # the previous round used to prove the (now-removed) raise fired on real
  # behaviour. It now proves the opposite: recovery still stops cleanly
  # instead of guessing, and the whole node survives as one unit.
  def test_a_deleted_formatting_artefact_no_longer_aborts
    text = "This is a sentence{b^>3<b^} with markup noise. Second sentence follows now."
    assert_equal [0], @segmenter.split_offsets(text, language: "en")
  end

  # L2 (fix round 2): an empty sentence from upstream must not emit a
  # duplicate, non-increasing offset (it would otherwise resolve to the
  # cursor's current position without advancing it). Exercised directly
  # against #recover_offsets, since no real pragmatic_segmenter input found
  # to reproduce an empty sentence -- this documents the guarantee the
  # method makes about its own input, not a specific upstream trigger.
  def test_an_empty_sentence_from_upstream_does_not_produce_a_duplicate_offset
    shadow = "Sentence one. Sentence two."
    sentences = ["Sentence one.", "", "Sentence two."]

    offsets = @segmenter.send(:recover_offsets, shadow, sentences)

    assert_equal offsets.sort.uniq, offsets
    assert_equal [0, "Sentence one. ".length], offsets
  end

  # M1 (fix round 2): DeepL, this gem's own flagship adapter, sends uppercase
  # and region-tagged codes ("RU", "EN-GB"). pragmatic_segmenter's own lookup
  # is case-sensitive and region-blind, so without normalising first, these
  # would silently fall through to Common rather than to the documented
  # English fallback, or (worse) simply fail to find Russian rules at all.
  def test_language_codes_are_normalised_before_reaching_pragmatic_segmenter
    text = "Проф. Иванов пришёл домой. Было поздно."
    expected = [0, "Проф. Иванов пришёл домой. ".length]

    ["ru", "RU", :RU, "ru-RU", "ru_RU"].each do |language|
      assert_equal expected, @segmenter.split_offsets(text, language: language),
                   "language: #{language.inspect}"
    end
  end

  # An unrecognised code, once normalised, lands on the documented English
  # fallback (DEFAULT_LANGUAGE) rather than silently on
  # PragmaticSegmenter::Languages::Common.
  def test_an_unrecognised_language_code_falls_back_to_english_rules
    text = "Проф. Иванов пришёл домой. Было поздно."
    offsets = @segmenter.split_offsets(text, language: "zz-nonsense")

    assert_equal [0, "Проф. ".length, "Проф. Иванов пришёл домой. ".length], offsets
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
