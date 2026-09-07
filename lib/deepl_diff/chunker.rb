# frozen_string_literal: true

class DeepLDiff::Chunker
  class Error < StandardError; end

  Chunk = Struct.new(:texts, :escaped_size)

  # No defaults. With one provider a default looks meaningful; with two it
  # silently lies about the second, which is the class of bug this file
  # already had once.
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

  # What the limit is about is the size of the request that goes over the
  # wire, so every measurement here is of the escaped form. Mixing it with
  # String#size lets a chunk of non-ASCII text run several times over.
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
