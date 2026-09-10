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

  # Response.build's new decoding step must be a no-op for the one provider that never escapes anything.
  def test_translate_does_not_touch_text_that_only_looks_like_it_needs_decoding
    texts = ["AT&T merged.", "5 < 7 is true.", "He didn't go."]
    request = TranslationDiff::Translation::Request.new(texts: texts, from: :en, to: :ru)

    assert_equal texts, provider.translate(request).texts
  end

  def test_cache_key_is_null
    assert_equal "null", provider.cache_key
  end
end
