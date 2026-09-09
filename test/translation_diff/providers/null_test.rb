require "test_helper"
require "support/provider_contract"

class NullProviderTest < Minitest::Test
  include ProviderContract

  def provider
    TranslationDiff::Providers::Null.new(TranslationDiff::Configuration.new)
  end

  def test_translate_returns_the_input_unchanged
    request = TranslationDiff::Translation::Request.new(texts: %w[one two], from: :en, to: :ru)

    assert_equal %w[one two], provider.translate(request).texts
  end

  def test_cache_key_is_null
    assert_equal "null", provider.cache_key
  end
end
