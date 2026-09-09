require "test_helper"

class SpacingTest < Minitest::Test
  def test_restores_trailing_spaces
    assert_equal "А   ", TranslationDiff::Spacing.restore("a   ", "А")
  end

  def test_restores_leading_and_trailing_spaces
    assert_equal "  Б ", TranslationDiff::Spacing.restore("  b ", "Б")
  end
end
