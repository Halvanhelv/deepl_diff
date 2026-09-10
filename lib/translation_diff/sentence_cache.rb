# Reads and writes sentence translations under the pipeline's cache key format, without touching the caller's array.
class TranslationDiff::SentenceCache
  # Its own class, so rescuing an unusable option cannot also swallow a store or provider failure.
  class Error < TranslationDiff::Error; end

  # The value types the key format can render. An allowlist: what it cannot render must raise, not be guessed at.
  SCALARS = [String, Symbol, Numeric, TrueClass, FalseClass, NilClass].freeze

  def initialize(store:, provider:, from:, to:, options: {})
    @store = store
    @provider = provider
    @from = from.downcase
    @to = to.downcase
    @options = options
  end

  # provider:from:to:sentence, with a digest of the per-call options wedged in as a field of its own when there are any.
  def key(segment)
    [@provider, @from, @to, *options_digest, Digest::MD5.hexdigest(segment.body)].join(":")
  end

  # Sets a translation on every segment the store already has cached, and hands back the rest as a new array.
  def fill(segments)
    values = @store.read_multi(segments.map { |segment| key(segment) })
    misses = []
    segments.each_with_index do |segment, index|
      value = values[index]
      value.nil? ? misses << segment : segment.translation = value
    end
    misses
  end

  # Writes back only the segments that carry a translation; an untranslated segment has nothing worth caching.
  # A store that batches gets one call; one that does not keeps the per-key contract it was written against.
  def store(segments)
    translated = segments.select(&:translated?)
    return translated.each { |segment| @store.write(key(segment), segment.translation) } if legacy_store?

    @store.write_multi(translated.map { |segment| [key(segment), segment.translation] })
    translated
  end

  private

  # A store written against the write-only contract, before write_multi existed, cannot be handed a batch.
  def legacy_store? = !@store.respond_to?(:write_multi)

  # No options contributes no field at all, which is the four-field key every already-warm cache is keyed on.
  def options_digest
    return [] if @options.empty?

    [Digest::MD5.hexdigest(canonical_options)[0, 8]]
  end

  # Sorted on the name's string form, because a Symbol and a String key are not comparable with each other.
  def canonical_options
    @options.sort_by { |name, _| name.to_s }.map { |name, value| "#{name}=#{canonical(name, value)}" }.join(",")
  end

  # A Hash canonicalises the way the options hash itself does, an Array its elements in order, joined the same way.
  def canonical(name, value)
    case value
    when Hash then value.sort_by { |k, _| k.to_s }.map { |k, v| "#{k}=#{canonical(name, v)}" }.join(",")
    when Array then value.map { |element| canonical(name, element) }.join(",")
    else scalar(name, value)
    end
  end

  # A key that is silently wrong costs a caller their whole cache and tells them nothing, so refuse to build one.
  def scalar(name, value)
    return value.inspect if SCALARS.any? { |type| value.is_a?(type) }

    raise Error, "cache option #{name} (a #{value.class}) has no stable string form"
  end
end
