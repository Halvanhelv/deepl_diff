# Reads and writes sentence translations under the pipeline's cache key format, without touching the caller's array.
class TranslationDiff::SentenceCache
  # Its own class, so rescuing an unusable option cannot also swallow a store or provider failure.
  class Error < TranslationDiff::Error; end

  # Ruby's default rendering of an object is its address, which would move the key every process.
  ADDRESS = /#<[^>]*0x\h+/

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
  def store(segments)
    segments.select(&:translated?).each { |segment| @store.write(key(segment), segment.translation) }
  end

  private

  # No options contributes no field at all, which is the four-field key every already-warm cache is keyed on.
  def options_digest
    return [] if @options.empty?

    [Digest::MD5.hexdigest(canonical_options)[0, 8]]
  end

  # Sorted on the name's string form, because a Symbol and a String key are not comparable with each other.
  def canonical_options
    @options.sort_by { |name, _| name.to_s }.map { |name, value| "#{name}=#{stable(name, value)}" }.join("&")
  end

  # A value that renders as an address makes a key nothing can ever hit twice, so say so where a caller will see it.
  def stable(name, value)
    rendered = value.inspect
    raise Error, "cache option #{name} (a #{value.class}) has no stable string form" if rendered.match?(ADDRESS)

    rendered
  end
end
