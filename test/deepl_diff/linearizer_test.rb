# frozen_string_literal: true

require "test_helper"

class LinearizerTest < Minitest::Test
  CASES = {
    "a_single_value" => "Value",
    "an_array" => [1, :two, "Three"],
    "a_nested_hash" => { a: "1", b: 2, c: { d: :three } }
  }.freeze

  CASES.each do |name, value|
    define_method(:"test_round_trips_#{name}") do
      linearized = DeepLDiff::Linearizer.linearize(value)

      assert_equal value, DeepLDiff::Linearizer.restore(value, linearized)
    end
  end
end
