# frozen_string_literal: true

# One hierarchy for everything that can go wrong, so a caller handles a rate
# limit the same way whichever provider raised it.
#
# The three branches answer three different questions. ConfigurationError
# means the caller set something up wrong and no request was made.
# ProviderError means the service answered and said no. TransportError means
# nobody answered. ResponseError means the answer was well-formed HTTP but
# broke this library's contract.
#
# No error carries the text being translated. Errors are logged, and this
# library handles other people's content.
module TranslationDiff
  class ConfigurationError < Error; end

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
    # Seconds the provider asked us to wait, when it said so at all. Faraday's
    # retry middleware honours the header itself; this is for a caller who
    # rescues the error after the retries are exhausted and wants to schedule
    # its own attempt.
    attr_reader :retry_after

    def initialize(message, provider: nil, status: nil, retry_after: nil)
      super(message, provider: provider, status: status)
      @retry_after = retry_after
    end
  end

  class TransportError < Error; end
  class ResponseError < Error; end
end
