# No error carries the text being translated -- errors are logged, and this library handles other people's content.
module TranslationDiff
  # Common ancestor for every error this gem raises, so `rescue TranslationDiff::Error` is enough.
  class Error < StandardError; end

  class ConfigurationError < Error; end

  # Raised by whichever limiter is configured, so a caller rescues one class rather than the one it happens to use.
  class RateLimitExceeded < Error; end

  # Raised before any request: the pair is checked against data captured from the vendor, not by asking it.
  class UnsupportedLanguageError < Error; end

  class ProviderError < Error
    attr_reader :provider, :status

    def initialize(message, provider: nil, status: nil)
      super(message)
      @provider = provider
      @status = status
    end
  end

  class AuthenticationError < ProviderError; end
  class QuotaExceededError < ProviderError; end
  class InvalidRequestError < ProviderError; end
  class ServiceError < ProviderError; end

  class RateLimitError < ProviderError
    # Faraday's retry middleware already honours this header; it's here for a caller scheduling its own retry.
    attr_reader :retry_after

    def initialize(message, provider: nil, status: nil, retry_after: nil)
      super(message, provider: provider, status: status)
      @retry_after = retry_after
    end
  end

  class TransportError < Error; end
  class ResponseError < Error; end

  # Its own class, not the generic Error, so rescuing "wrong shape" can't also swallow an option-name collision.
  class InvalidProviderError < Error; end
end
