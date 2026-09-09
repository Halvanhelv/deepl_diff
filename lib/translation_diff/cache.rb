class TranslationDiff::Cache
  class Error < TranslationDiff::Error; end

  # 32 bits of digest is ample to keep option sets apart without bloating every key in the cache.
  DIGEST_LENGTH = 8

  # No attr_reader for `store`: #store is already the public method that writes translations back.
  def initialize(from, to, provider:, store:, options: {})
    @from = from
    @to = to
    @provider = provider
    @store = store
    @options = options
  end

  def cached_and_missing(values)
    keys = values.map { |v| key(v) }
    cached = @store.read_multi(keys)
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
    @store.write(key(value), translation)
    translation
  end

  def key(value)
    hash = Digest::MD5.hexdigest(value.strip) # No matter how much spaces

    [provider, language(from), language(to), options_digest, hash].compact.join(":")
  end

  # "EN" and :en are the same language; also must never introduce a colon, the key-join separator.
  def language(code)
    code.to_s.downcase
  end

  # Two calls differing only in formality or glossary must not share a key.
  def options_digest
    return @options_digest if defined?(@options_digest)

    @options_digest = options.empty? ? nil : Digest::MD5.hexdigest(canonical(options))[0, DIGEST_LENGTH]
  end

  # Object#inspect isn't stable: Ruby 3.4 changed hash rendering, and default #inspect embeds an address.
  def canonical(value)
    case value
    when Hash then value.sort_by { |key, _| key.to_s }.map { |key, item| "#{key}=#{canonical(item)}" }.join(",")
    when Array then value.map { |item| canonical(item) }.join(",")
    when String, Symbol, Numeric, true, false, nil then value.inspect
    else raise Error, "Cannot build a stable cache key from #{value.class} in the provider options"
    end
  end
end
