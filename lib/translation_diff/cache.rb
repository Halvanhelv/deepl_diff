# frozen_string_literal: true

class TranslationDiff::Cache
  class Error < TranslationDiff::Error; end

  # An application uses a handful of distinct option sets, so 32 bits of
  # digest is ample to keep them apart; the full 128-bit MD5 would just
  # bloat every key in a cache that may hold millions of them.
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
  # for identical work. The collision argument for #key depends on none of
  # its segments containing a colon: from/to are caller-supplied, so this
  # normalisation must not introduce one.
  def language(code)
    code.to_s.downcase
  end

  # Two calls differing only in formality or glossary are two different
  # translations and must not share a key.
  def options_digest
    return @options_digest if defined?(@options_digest)

    @options_digest = options.empty? ? nil : Digest::MD5.hexdigest(canonical(options))[0, DIGEST_LENGTH]
  end

  # Object#inspect is not a stable serialisation: Ruby 3.4 changed how
  # symbol-keyed hashes render, and an object without its own #inspect embeds
  # a memory address. Either would silently change every cache key and make
  # the application pay for every translation a second time.
  def canonical(value)
    case value
    when Hash then value.sort_by { |key, _| key.to_s }.map { |key, item| "#{key}=#{canonical(item)}" }.join(",")
    when Array then value.map { |item| canonical(item) }.join(",")
    when String, Symbol, Numeric, true, false, nil then value.inspect
    else raise Error, "Cannot build a stable cache key from #{value.class} in the provider options"
    end
  end

  def cache_store
    TranslationDiff.cache_store
  end
end
