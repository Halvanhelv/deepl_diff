# frozen_string_literal: true

require "test_helper"

class DeepLDiffTest < Minitest::Test
  def test_has_a_version_number
    refute_nil DeepLDiff::VERSION
  end
end
