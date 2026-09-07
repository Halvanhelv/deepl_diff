# frozen_string_literal: true

# Hands back what it was given. For tests, and for wiring a pipeline up
# before a real provider is available.
class DeepLDiff::Adapters::Null
  # No #detect on purpose: detection is optional in the contract, and this
  # is the adapter that proves the optional branch works.
  # rubocop:disable-next Lint/UnusedMethodArgument
  def translate(texts, from:, to:, **options)
    texts.map(&:to_s)
  end

  def max_request_size = 1_000_000
  def max_batch_size = 1_000_000
  def cache_key = "null"
end
