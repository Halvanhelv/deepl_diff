# Segments grouped to one provider request; a reply lands back on them through #apply, never by position after the fact.
class TranslationDiff::Batch
  attr_reader :segments

  def initialize(segments)
    @segments = segments
  end

  def texts = segments.map(&:core)

  # Each translation lands on the segment at the same index in this batch, the segment that produced it.
  def apply(translations)
    ensure_reply_size!(translations)
    segments.each_with_index { |segment, index| segment.translation = translations[index] }
  end

  class << self
    # Skips blank segments -- a provider has no use for whitespace -- then fills batches within both declared limits.
    def pack(segments, capabilities:)
      filler = Filler.new(capabilities)
      segments.reject(&:empty?).each { |segment| filler.add(segment) }
      filler.batches
    end
  end

  private

  def ensure_reply_size!(translations)
    return if translations.size == segments.size

    raise TranslationDiff::ResponseError,
          "Provider returned #{translations.size} translations for #{segments.size} segments"
  end

  # Fills one batch until its count or its cumulative escaped size would cross the limit, then starts the next.
  class Filler
    def initialize(capabilities)
      @capabilities = capabilities
      @batches = []
      @current = []
      @current_size = 0
    end

    def add(segment)
      size = escaped_size(segment)
      flush if full?(size)
      @current << segment
      @current_size += size
    end

    def batches
      flush
      @batches
    end

    private

    # Escaped, because that is the size a provider's own limit is documented against and what goes over the wire.
    def escaped_size(segment)
      size = CGI.escape(segment.core).size
      ensure_sendable!(segment, size)
      size
    end

    # A text over either declared limit can never be sent, alone or otherwise, so this raises before any batch fills.
    def ensure_sendable!(segment, size)
      limit = [@capabilities.max_request_size, @capabilities.max_text_size].compact.min
      return if size <= limit

      raise TranslationDiff::Error,
            "#{preview(segment.core)} is #{size} characters once escaped, over this provider's limit of #{limit}"
    end

    # A short prefix locates the offending text without reproducing it -- the rest is the customer's content.
    def preview(text)
      return text.dup if text.size <= 20

      "#{text[0, 20]}..."
    end

    def full?(size)
      return false if @current.empty?

      @current.size >= @capabilities.max_batch_size || @current_size + size > @capabilities.max_request_size
    end

    def flush
      return if @current.empty?

      @batches << TranslationDiff::Batch.new(@current)
      @current = []
      @current_size = 0
    end
  end
end
