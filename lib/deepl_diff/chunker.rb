# frozen_string_literal: true

class DeepLDiff::Chunker
  class Error < StandardError; end

  Chunk = Struct.new(:texts, :bytesize)

  MAX_CHUNK_SIZE = 1700
  COUNT_LIMIT = 300

  def initialize(values, limit: MAX_CHUNK_SIZE, count_limit: COUNT_LIMIT)
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
      (size(value) + tail.bytesize > limit) ||
      tail.texts.size > count_limit
  end

  def size(text)
    CGI.escape(text).size
  end

  def update_chunk(chunk, value)
    chunk.texts << value
    chunk.bytesize += value.size
  end

  def validate_value_size(value)
    raise Error, "Too long part #{value.size} > #{limit}" if value.size > limit
  end
end
