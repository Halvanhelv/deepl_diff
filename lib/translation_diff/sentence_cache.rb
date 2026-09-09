# Reads and writes sentence translations under the pipeline's cache key format, without touching the caller's array.
class TranslationDiff::SentenceCache
  # Segment strips this same class of whitespace into leading/trailing padding; this recovers the undecoded body.
  UNPADDED = /[^[:space:]].*[^[:space:]]|[^[:space:]]/m

  def initialize(store:, provider:, from:, to:, options: {})
    @store = store
    @provider = provider
    @from = from.downcase
    @to = to.downcase
    @options = options
  end

  # provider:from:to, then one digest covering both the per-call options and the sentence as it appeared in markup.
  def key(segment)
    "#{@provider}:#{@from}:#{@to}:#{Digest::MD5.hexdigest("#{options_digest}#{raw_text(segment)}")}"
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

  # Empty for the common case of no per-call options, which is what the recorded baseline keys assume.
  def options_digest = @options.empty? ? "" : @options.sort.to_s

  # The sentence as it appeared in markup, before entity decoding, which is what the recorded keys were hashed from.
  def raw_text(segment) = segment.source.partition(UNPADDED)[1]
end
