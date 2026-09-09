# frozen_string_literal: true

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

  # A short response means nils get shifted into the results and surface much
  # later as a NoMethodError far from the cause. The check lives in the
  # constructor rather than in a base-class method so that it still holds for
  # a provider that overrides #translate outright.
  def test_build_raises_when_the_provider_returned_the_wrong_number_of_texts
    error = assert_raises(TranslationDiff::ResponseError) do
      TranslationDiff::Translation::Response.build(request: request, texts: %w[один])
    end

    assert_match(/1/, error.message)
    assert_match(/2/, error.message)
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
