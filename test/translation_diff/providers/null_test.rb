# frozen_string_literal: true

require "test_helper"
require "support/provider_contract"

class NullProviderTest < Minitest::Test
  include ProviderContract

  def provider
    TranslationDiff::Providers::Null.new
  end

  def test_translate_returns_the_input_unchanged
    assert_equal %w[one two], provider.translate(%w[one two], from: :en, to: :ru)
  end
end
