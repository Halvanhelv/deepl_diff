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
    # Multiple blank lines, untouched by shadowing: SINGLE_NEWLINE only matches "\n" with no adjoining "\n".
    ["First paragraph.\n\n\nSecond paragraph.\n\n\n\nThird paragraph.", "en"],
    ["見て。すごい！次はどうなる？", "ja"],
    ["Проф. Иванов пришёл домой. Было поздно.", "ru"],
    ["سؤال وجواب: ماذا حدث؟ طرح الكثير من التساؤلات.", "ar"],
    ["Ի՞նչ ես մտածում: Ոչինչ:", "hy"],
    # Single newlines (shadowed) and a blank-line paragraph break (not), together, exercising both paths.
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

  # Without a language, pragmatic_segmenter falls back to English rules, which read "Проф." as a full sentence.
  def test_without_a_language_russian_abbreviations_are_mis_segmented
    text = "Проф. Иванов пришёл домой. Было поздно."
    offsets = @segmenter.split_offsets(text)

    assert_equal [0, "Проф. ".length, "Проф. Иванов пришёл домой. ".length], offsets
  end

  # Proves the language argument is actually threaded through to pragmatic_segmenter, not merely accepted.
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

  # pragmatic_segmenter treats any single newline as a sentence boundary, confirmed false on wrapped prose.
  def test_a_single_newline_with_no_punctuation_does_not_split_the_sentence
    text = "Some text \n continues here without any punctuation at the break"
    assert_equal [0], @segmenter.split_offsets(text)
  end

  def test_a_single_newline_between_two_real_sentences_is_preserved_as_a_boundary_gap
    text = "This is a sentence\ncut off by a line wrap. A second sentence follows."
    offsets = @segmenter.split_offsets(text, language: "en")

    assert_equal [0, "This is a sentence\ncut off by a line wrap. ".length], offsets
  end

  # A blank-line run is a real paragraph break; shadowing deliberately leaves it alone.
  def test_a_blank_line_paragraph_break_still_splits
    text = "Первое предложение.\n\nВторое предложение."
    offsets = @segmenter.split_offsets(text, language: "ru")

    assert_equal [0, "Первое предложение.\n\n".length], offsets
  end

  # Shadowing fixes the real trigger reported in the previous round: this no longer raises.
  def test_the_japanese_newline_after_a_common_particle_now_segments_instead_of_raising
    text = "これは父の\n家です。それはペンです。"
    offsets = @segmenter.split_offsets(text, language: "ja")

    assert_equal [0, "これは父の\n家です。".length], offsets
  end

  # H1 (fix round 2): pragmatic_segmenter's cleaner respaces "Ph.D." into "Ph. D.", a real reproduced trigger.
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

  # pragmatic_segmenter's InlineFormattingRule deletes this artefact outright; recovery now stops cleanly instead.
  def test_a_deleted_formatting_artefact_no_longer_aborts
    text = "This is a sentence{b^>3<b^} with markup noise. Second sentence follows now."
    assert_equal [0], @segmenter.split_offsets(text, language: "en")
  end

  # N3 (fix round 4): coarsening must not throw away a boundary already proved verbatim character for character.
  def test_a_verified_boundary_before_an_unrecoverable_sentence_is_not_discarded
    text = "First is fine. Hello   world mid. Third one here."
    offsets = @segmenter.split_offsets(text, language: "en")

    assert_equal [0, "First is fine.".length], offsets
    assert_equal text, reconstruct(text, offsets)
  end

  # L2 (fix round 2): exercised directly against #recover_offsets; no real input was found to reproduce this.
  def test_an_empty_sentence_from_upstream_does_not_produce_a_duplicate_offset
    shadow = "Sentence one. Sentence two."
    sentences = ["Sentence one.", "", "Sentence two."]

    offsets = @segmenter.send(:recover_offsets, shadow, sentences)

    assert_equal offsets.sort.uniq, offsets
    assert_equal [0, "Sentence one. ".length], offsets
  end

  # M1 (fix round 2): DeepL sends codes like "EN-GB"; the lookup is case-sensitive and region-blind.
  def test_language_codes_are_normalised_before_reaching_pragmatic_segmenter
    text = "Проф. Иванов пришёл домой. Было поздно."
    expected = [0, "Проф. Иванов пришёл домой. ".length]

    ["ru", "RU", :RU, "ru-RU", "ru_RU"].each do |language|
      assert_equal expected, @segmenter.split_offsets(text, language: language),
                   "language: #{language.inspect}"
    end
  end

  # "Dr.Smith" distinguishes English from Common fallback where the Russian fixture above cannot.
  def test_an_unrecognised_language_code_falls_back_to_english_rules
    text = "This ends here.Next sentence starts."
    offsets = @segmenter.split_offsets(text, language: "zz-nonsense")

    assert_equal [0, "This ends here.".length], offsets
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
