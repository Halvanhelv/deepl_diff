class TranslationDiff::Chunker
  class Error < TranslationDiff::Error; end

  Chunk = Struct.new(:texts, :escaped_size)

  # No defaults: a default silently lies about the second provider, a bug this file already had once.
  def initialize(values, limit:, count_limit:)
    @values = values
    @limit = limit
    @count_limit = count_limit
  end

  def call
    chunks.map(&:texts)
  end

  def chunks
    values.each_with_object([]) do |value, chunks|
      validate_value_size(value)

      tail = chunks.last

      if next_chunk?(tail, value)
        chunks << Chunk.new([], 0)
        tail = chunks.last
      end

      update_chunk(tail, value)
    end
  end

  private

  attr_reader :values, :limit, :count_limit

  def next_chunk?(tail, value)
    tail.nil? ||
      (escaped_size(value) + tail.escaped_size > limit) ||
      tail.texts.size >= count_limit
  end

  # The limit is on wire size, so measure the escaped form -- String#size lets non-ASCII text run over.
  def escaped_size(text)
    CGI.escape(text).size
  end

  def update_chunk(chunk, value)
    chunk.texts << value
    chunk.escaped_size += escaped_size(value)
  end

  def validate_value_size(value)
    size = escaped_size(value)

    raise Error, "Too long part #{size} > #{limit}" if size > limit
  end
end
