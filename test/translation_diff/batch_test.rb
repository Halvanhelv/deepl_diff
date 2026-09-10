require "test_helper"

class BatchTest < Minitest::Test
  def capabilities(request_size: 1_000, batch_size: 10, text_size: nil)
    TranslationDiff::Capabilities.new(
      max_request_size: request_size, max_batch_size: batch_size, max_text_size: text_size,
      html: :none, notranslate: false, detects_language: false, reports_billing: false
    )
  end

  def segments(*sources) = sources.map { |s| TranslationDiff::Segment.new(s) }

  def pack(sources, **)
    TranslationDiff::Batch.pack(segments(*sources), capabilities: capabilities(**))
  end

  def test_everything_fits_in_one_batch_when_it_fits
    batches = pack(%w[one two three])

    assert_equal 1, batches.size
    assert_equal %w[one two three], batches.first.texts
  end

  def test_the_count_limit_starts_a_new_batch
    batches = pack(%w[one two three four five], batch_size: 2)

    assert_equal [%w[one two], %w[three four], %w[five]], batches.map(&:texts)
  end

  def test_the_size_limit_starts_a_new_batch
    batches = pack(%w[aaaa bbbb cccc], request_size: 9)

    assert_equal [%w[aaaa bbbb], %w[cccc]], batches.map(&:texts)
  end

  # A provider that cannot batch gets one text per request, and that is
  # correct rather than a degenerate case -- Amazon Translate has no batch
  # form of its endpoint at all.
  def test_a_batch_size_of_one_produces_one_request_per_text
    assert_equal [%w[one], %w[two], %w[three]], pack(%w[one two three], batch_size: 1).map(&:texts)
  end

  # Size is the escaped length, because that is what goes over the wire.
  def test_size_is_measured_escaped_not_in_characters
    batches = pack(%w[привет привет], request_size: 40)

    assert_equal 2, batches.size, "each Cyrillic word is 36 escaped characters"
  end

  # A caller who wants to catch "too long for this provider" must not also catch an unrelated registry miss.
  def test_a_text_larger_than_the_request_limit_raises_naming_the_limit
    error = assert_raises(TranslationDiff::Batch::Error) { pack(["x" * 50], request_size: 10) }

    assert_match(/10/, error.message)
    assert_match(/50/, error.message)
  end

  # The error locates the sentence without reproducing it: the whole sentence
  # is the customer's content and this message may be logged.
  def test_the_too_long_error_does_not_carry_the_whole_sentence
    sentence = "Secret #{'y' * 200}"
    error = assert_raises(TranslationDiff::Batch::Error) { pack([sentence], request_size: 10) }

    refute_includes error.message, "y" * 200
  end

  def test_apply_puts_each_translation_on_its_own_segment
    batch = pack(%w[one two]).first
    batch.apply(%w[один два])

    assert_equal %w[один два], batch.segments.map(&:translation)
  end

  def test_apply_refuses_a_reply_of_the_wrong_length
    batch = pack(%w[one two]).first

    assert_raises(TranslationDiff::ResponseError) { batch.apply(%w[один]) }
  end

  def test_empty_segments_are_never_packed
    batches = TranslationDiff::Batch.pack(segments("one", "   ", "two"), capabilities: capabilities)

    assert_equal [%w[one two]], batches.map(&:texts)
  end

  def test_no_segments_produce_no_batches
    assert_empty TranslationDiff::Batch.pack([], capabilities: capabilities)
  end
end
