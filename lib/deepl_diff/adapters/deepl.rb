# frozen_string_literal: true

# Wraps a deepl-rb client. That gem is not a dependency of this one: the
# client arrives as an argument and the ::DeepL default resolves at call
# time, so an application that never uses this adapter never needs it.
class DeepLDiff::Adapters::DeepL
  # DeepL requires a target language even when only the detection is
  # wanted, so the adapter picks one rather than making the caller do it.
  DETECTION_TARGET = "EN"

  MAX_REQUEST_SIZE = 1700
  MAX_BATCH_SIZE = 300

  def initialize(client = ::DeepL)
    @client = client
  end

  def translate(texts, from:, to:, **options)
    Array(@client.translate(texts, from, to, options)).map(&:text)
  end

  def detect(text)
    @client.translate(text, nil, DETECTION_TARGET)
           .detected_source_language
           .downcase
  end

  def max_request_size = MAX_REQUEST_SIZE
  def max_batch_size = MAX_BATCH_SIZE
  def cache_key = "deepl"

  private

  attr_reader :client
end
