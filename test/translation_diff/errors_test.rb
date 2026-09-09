# frozen_string_literal: true

require "test_helper"

class ErrorsTest < Minitest::Test
  # A caller who wants to rescue anything this gem raises writes one rescue.
  def test_every_error_descends_from_the_common_ancestor
    [TranslationDiff::ConfigurationError, TranslationDiff::ProviderError,
     TranslationDiff::AuthenticationError, TranslationDiff::RateLimitError,
     TranslationDiff::QuotaExceededError, TranslationDiff::InvalidRequestError,
     TranslationDiff::ServiceError, TranslationDiff::TransportError,
     TranslationDiff::ResponseError].each do |klass|
      assert_operator klass, :<, TranslationDiff::Error
    end
  end

  # Rescuing "the provider said no" must not also catch a config mistake or a socket timeout.
  def test_provider_errors_are_a_family_of_their_own
    [TranslationDiff::AuthenticationError, TranslationDiff::RateLimitError,
     TranslationDiff::QuotaExceededError, TranslationDiff::InvalidRequestError,
     TranslationDiff::ServiceError].each do |klass|
      assert_operator klass, :<, TranslationDiff::ProviderError
    end

    refute_operator TranslationDiff::ConfigurationError, :<, TranslationDiff::ProviderError
    refute_operator TranslationDiff::TransportError, :<, TranslationDiff::ProviderError
  end

  def test_a_provider_error_carries_the_provider_and_the_status
    error = TranslationDiff::RateLimitError.new("slow down", provider: :deepl, status: 429,
                                                             retry_after: 30)

    assert_equal :deepl, error.provider
    assert_equal 429, error.status
    assert_equal 30, error.retry_after
    assert_equal "slow down", error.message
  end

  def test_retry_after_is_nil_when_the_provider_did_not_say
    error = TranslationDiff::RateLimitError.new("slow down", provider: :deepl, status: 429)

    assert_nil error.retry_after
  end
end
