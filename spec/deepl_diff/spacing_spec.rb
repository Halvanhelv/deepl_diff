# frozen_string_literal: true

require "spec_helper"

RSpec.describe DeepLDiff::Spacing do
  [
    ["a   ", "А", "А   ", ""],
    ["  b ", "Б", "  Б ", ""]
  ].each do |(left, right, result)|
    it { expect(described_class.restore(left, right)).to eq(result) }
  end
end
