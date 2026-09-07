# frozen_string_literal: true

require "test_helper"

class SpacingTest < Minitest::Test
  def test_restores_trailing_spaces
    assert_equal "А   ", DeepLDiff::Spacing.restore("a   ", "А")
  end

  def test_restores_leading_and_trailing_spaces
    assert_equal "  Б ", DeepLDiff::Spacing.restore("  b ", "Б")
  end
end
