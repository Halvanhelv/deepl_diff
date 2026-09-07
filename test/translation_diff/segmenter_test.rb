# frozen_string_literal: true

require "test_helper"

class SegmenterTest < Minitest::Test
  RECONSTRUCTION_SAMPLES = [
    "Ordinary text. With two sentences.",
    "",
    "   ",
    "No terminator here at all",
    "Ends mid-sentence without a stop",
    "Ends with a stop.",
    "Wait!!! Really?! Yes.",
    "Смеркалось. Ворчало. Кричало.",
    "Набор «Солнечная механика» от 4М — это 6 экспериментов.\n\n" \
    "Юному изобретателю предстоит воочию посмотреть на чудеса.",
    "見て。すごい！",
    "3.14 is pi. 1.2.3 is a version.",
    "Visit https://example.com. Thanks.",
    "Mail user@example.com. Thanks.",
    "Dr. Smith went home.",
    "А. С. Пушкин родился в Москве.",
    "Стоимость 5 руб. Доставка бесплатно."
  ].freeze

  def setup
    @segmenter = TranslationDiff::Segmenter.new
  end

  def test_reconstruction_invariant_holds_for_a_variety_of_inputs
    RECONSTRUCTION_SAMPLES.each { |text| assert_reconstructs(text) }
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

  def test_terminator_at_the_end_with_no_trailing_whitespace_is_not_split
    assert_equal [0], @segmenter.split_offsets("Ends with a stop.")
  end

  def test_ordinary_sentence_boundary_splits
    text = "Hello there. Goodbye now."
    assert_equal [0, "Hello there. ".length], @segmenter.split_offsets(text)
  end

  def test_consecutive_terminators_are_treated_as_one_run
    text = "Wait!!! Really?! Yes."
    offsets = @segmenter.split_offsets(text)

    assert_equal [0, "Wait!!! ".length, "Wait!!! Really?! ".length], offsets
  end

  def test_cjk_terminators_split_without_requiring_whitespace
    text = "見て。すごい！"
    assert_equal [0, "見て。".length], @segmenter.split_offsets(text)
  end

  def test_cjk_terminator_at_the_very_end_is_not_a_dangling_boundary
    assert_equal [0], @segmenter.split_offsets("見て。")
  end

  # Guard 1: the next visible character is lowercase.
  def test_guard_lowercase_letter_after_terminator_blocks_the_split
    assert_equal [0], @segmenter.split_offsets("Wow. amazing things happened.")
  end

  def test_guard_uppercase_letter_after_terminator_does_not_block_the_split
    text = "Done. Next starts."
    assert_equal [0, "Done. ".length], @segmenter.split_offsets(text)
  end

  # Guard 2: a known abbreviation precedes the period.
  def test_guard_known_abbreviation_blocks_the_split
    assert_equal [0], @segmenter.split_offsets("See Dr. Smith today.")
  end

  def test_guard_abbreviation_is_case_insensitive
    assert_equal [0], @segmenter.split_offsets("See DR. Smith today.")
  end

  def test_guard_russian_abbreviation_blocks_the_split
    assert_equal [0], @segmenter.split_offsets("См. рис.")
  end

  # Guard 3: a single letter precedes the period (initials).
  def test_guard_single_letter_initial_blocks_the_split
    text = "J. R. R. Tolkien wrote it."
    offsets = @segmenter.split_offsets(text)

    assert_equal [0], offsets
  end

  def test_guard_russian_initials_block_the_split
    assert_equal [0], @segmenter.split_offsets("А. С. Пушкин родился в Москве.")
  end

  # Guard 4: digits on both sides of the terminator.
  def test_guard_digits_on_both_sides_blocks_the_split
    assert_equal [0], @segmenter.split_offsets("Section 3. 4 follows it.")
  end

  def test_digit_before_and_uppercase_letter_after_still_splits
    text = "There were 3. Four came later."
    assert_equal [0, "There were 3. ".length], @segmenter.split_offsets(text)
  end

  # Guard 5: the period sits inside a URL or an email.
  def test_guard_url_blocks_the_split
    assert_equal [0], @segmenter.split_offsets("Visit https://example.com. Thanks.")
  end

  def test_guard_email_blocks_the_split
    assert_equal [0], @segmenter.split_offsets("Mail user@example.com. Thanks.")
  end

  def test_guard_url_without_trailing_period_still_splits_after_the_sentence
    text = "Visit https://example.com now. Thanks."
    assert_equal [0, "Visit https://example.com now. ".length], @segmenter.split_offsets(text)
  end

  private

  def assert_reconstruct_invariant(text, offsets)
    assert_equal 0, offsets.first, "first offset for #{text.inspect}"
    assert_equal offsets.sort.uniq, offsets, "offsets not sorted/unique for #{text.inspect}"

    reconstructed = offsets.each_cons(2).map { |a, b| text[a...b] }.join + text[offsets.last..]
    assert_equal text, reconstructed, "reconstruction failed for #{text.inspect}"
  end

  def assert_reconstructs(text)
    assert_reconstruct_invariant(text, @segmenter.split_offsets(text))
  end
end
