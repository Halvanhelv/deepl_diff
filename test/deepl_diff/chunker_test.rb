# frozen_string_literal: true

require "test_helper"

class ChunkerTest < Minitest::Test
  LIMIT = 20
  COUNT_LIMIT = 5

  LONG = "a" * 10
  MEDIUM = "a" * 7
  SHORT = "x"
  OVERSIZED = "a" * 30

  CASES = {
    "keeps_values_in_one_chunk_when_they_fit" => [
      %w[a b c],
      [%w[a b c]]
    ],
    "splits_on_the_size_limit" => [
      [LONG] * 3,
      [[LONG, LONG], [LONG]]
    ],
    "splits_between_values_of_uneven_size" => [
      ([MEDIUM] * 3) + [LONG],
      [[MEDIUM, MEDIUM], [MEDIUM, LONG]]
    ],
    "splits_on_the_count_limit" => [
      [SHORT] * 10,
      [[SHORT] * 6, [SHORT] * 4]
    ]
  }.freeze

  CASES.each do |name, (values, expected)|
    define_method(:"test_#{name}") do
      assert_equal expected, chunk(values)
    end
  end

  def test_raises_when_a_single_value_exceeds_the_limit
    error = assert_raises(DeepLDiff::Chunker::Error) { chunk([OVERSIZED]) }

    assert_match(/Too long part/, error.message)
  end

  private

  def chunk(values)
    DeepLDiff::Chunker.new(values, limit: LIMIT, count_limit: COUNT_LIMIT).call
  end
end
