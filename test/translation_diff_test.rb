# frozen_string_literal: true

require "test_helper"

class TranslationDiffTest < Minitest::Test
  def test_has_a_version_number
    refute_nil TranslationDiff::VERSION
  end
end
