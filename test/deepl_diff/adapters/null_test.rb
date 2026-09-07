# frozen_string_literal: true

require "test_helper"
require "support/adapter_contract"

class NullAdapterTest < Minitest::Test
  include AdapterContract

  def adapter
    DeepLDiff::Adapters::Null.new
  end

  def test_translate_returns_the_input_unchanged
    assert_equal %w[one two], adapter.translate(%w[one two], from: :en, to: :ru)
  end
end
