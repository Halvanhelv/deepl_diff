# frozen_string_literal: true

class DeepLDiff::Cache
  DIGEST_LENGTH = 8

  def initialize(from, to, provider:, options: {})
    @from = from
    @to = to
    @provider = provider
    @options = options
  end

  def cached_and_missing(values)
    keys = values.map { |v| key(v) }
    cached = cache_store.read_multi(keys)
    missing = values.map.with_index { |v, i| v if cached[i].nil? }.compact

    [cached, missing]
  end

  def store(values, cached, updates)
    cached.map.with_index do |value, index|
      value || store_value(values[index], updates.shift)
    end
  end

  private

  attr_reader :from, :to, :provider, :options

  def store_value(value, translation)
    cache_store.write(key(value), translation)
    translation
  end

  def key(value)
    hash = Digest::MD5.hexdigest(value.strip) # No matter how much spaces

    [provider, language(from), language(to), options_digest, hash].compact.join(":")
  end

  # "EN" and :en are the same language; without this they are two entries
  # for identical work.
  def language(code)
    code.to_s.downcase
  end

  # Two calls differing only in formality or glossary are two different
  # translations and must not share a key.
  def options_digest
    return @options_digest if defined?(@options_digest)

    @options_digest =
      if options.empty?
        nil
      else
        Digest::MD5.hexdigest(options.sort_by { |key, _| key.to_s }.inspect)[0, DIGEST_LENGTH]
      end
  end

  def cache_store
    DeepLDiff.cache_store
  end
end
