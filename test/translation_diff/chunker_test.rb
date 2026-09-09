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
      [[SHORT] * 5, [SHORT] * 5]
    ]
  }.freeze

  CASES.each do |name, (values, expected)|
    define_method(:"test_#{name}") do
      assert_equal expected, chunk(values)
    end
  end

  def test_raises_when_a_single_value_exceeds_the_limit
    error = assert_raises(TranslationDiff::Chunker::Error) { chunk([OVERSIZED]) }

    assert_match(/Too long part/, error.message)
  end

  # CGI.escape inflates Cyrillic sixfold; measuring raw String#size let chunks of non-ASCII text run over.
  def test_measures_non_ascii_values_by_their_escaped_size
    value = "я" * 3

    # Measured raw, both values fit in one chunk of 20; measured as sent, they cannot.
    assert_equal 3, value.size
    assert_equal 18, CGI.escape(value).size
    assert_equal [[value], [value]], chunk([value, value])
  end

  def test_raises_when_the_escaped_size_of_one_value_exceeds_the_limit
    error = assert_raises(TranslationDiff::Chunker::Error) { chunk(["я" * 4]) }

    assert_match(/Too long part 24 > 20/, error.message)
  end

  private

  def chunk(values)
    TranslationDiff::Chunker.new(values, limit: LIMIT, count_limit: COUNT_LIMIT).call
  end
end
