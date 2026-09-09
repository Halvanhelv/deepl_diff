require "test_helper"

class TranslationResponseTest < Minitest::Test
  def request(texts = %w[one two])
    TranslationDiff::Translation::Request.new(texts: texts, from: "en", to: "ru")
  end

  def test_a_request_defaults_its_options_to_an_empty_hash
    assert_empty TranslationDiff::Translation::Request.new(texts: %w[one], from: nil, to: "ru").options
  end

  def test_build_returns_the_texts_it_was_given
    response = TranslationDiff::Translation::Response.build(request: request, texts: %w[один два])

    assert_equal %w[один два], response.texts
  end

  # A short response would shift nils into the results, surfacing much later as a distant NoMethodError.
  def test_build_raises_when_the_provider_returned_the_wrong_number_of_texts
    error = assert_raises(TranslationDiff::ResponseError) do
      TranslationDiff::Translation::Response.build(request: request, texts: %w[один])
    end

    assert_match(/1/, error.message)
    assert_match(/2/, error.message)
  end

  # A nil translation used to reach the old pipeline's spacing step and die there as NoMethodError, naming nothing.
  def test_build_raises_when_a_translation_is_not_a_string
    error = assert_raises(TranslationDiff::ResponseError) do
      TranslationDiff::Translation::Response.build(request: request, texts: ["один", nil])
    end

    assert_match(/position 1/, error.message)
    assert_match(/NilClass/, error.message)
  end

  # Azure returns 200 for a batch where one element carries `error` instead of `translations`.
  def test_build_raises_for_a_nil_in_the_middle_of_a_batch
    batch = request(%w[one two three])

    error = assert_raises(TranslationDiff::ResponseError) do
      TranslationDiff::Translation::Response.build(request: batch, texts: ["один", nil, "три"])
    end

    assert_match(/position 1/, error.message)
  end

  def test_build_names_only_the_first_offending_position
    batch = request(%w[one two three])

    error = assert_raises(TranslationDiff::ResponseError) do
      TranslationDiff::Translation::Response.build(request: batch, texts: [nil, nil, 42])
    end

    assert_match(/position 0/, error.message)
    refute_match(/position 2/, error.message)
  end

  # The offending value is the customer's text or a provider's error object; neither belongs in a message.
  def test_build_names_the_class_but_never_the_offending_value
    error = assert_raises(TranslationDiff::ResponseError) do
      TranslationDiff::Translation::Response.build(request: request, texts: ["один", { "error" => "s3cret" }])
    end

    refute_match(/s3cret/, error.message)
    assert_match(/Hash/, error.message)
  end

  def test_detected_source_and_usage_default_to_nil
    response = TranslationDiff::Translation::Response.build(request: request, texts: %w[один два])

    assert_nil response.detected_source
    assert_nil response.usage
  end

  def test_usage_carries_what_the_provider_reported_and_nil_for_the_rest
    usage = TranslationDiff::Translation::Usage.new(characters: 40, billed_characters: 40)

    assert_equal 40, usage.characters
    assert_equal 40, usage.billed_characters
    assert_nil usage.tokens
    assert_nil usage.model
  end
end
