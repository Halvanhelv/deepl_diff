# frozen_string_literal: true

# The executable form of the provider contract. Every provider includes this
# and defines #provider; anything that passes can be registered with
# TranslationDiff::Providers.register and reached through TranslationDiff.translate.
module ProviderContract
  def test_translate_returns_one_string_per_input
    request = TranslationDiff::Translation::Request.new(texts: %w[one two three], from: :en, to: :ru)
    result = provider.translate(request)

    assert_equal 3, result.texts.size
    result.texts.each { |value| assert_kind_of String, value }
  end

  def test_translate_preserves_order
    texts = %w[first second third]
    individually = texts.map do |text|
      request = TranslationDiff::Translation::Request.new(texts: [text], from: :en, to: :ru)
      provider.translate(request).texts.first
    end
    batched_request = TranslationDiff::Translation::Request.new(texts: texts, from: :en, to: :ru)
    batched = provider.translate(batched_request).texts

    assert_equal 3, batched.size
    assert_equal individually, batched
  end

  def test_translate_accepts_provider_options
    request = TranslationDiff::Translation::Request.new(
      texts: %w[one], from: :en, to: :ru, options: { formality: :less }
    )
    result = provider.translate(request)

    assert_equal 1, result.texts.size
  end

  def test_max_request_size_is_a_positive_integer
    assert_kind_of Integer, provider.class.capabilities.max_request_size
    assert_operator provider.class.capabilities.max_request_size, :>, 0
  end

  def test_max_batch_size_is_a_positive_integer
    assert_kind_of Integer, provider.class.capabilities.max_batch_size
    assert_operator provider.class.capabilities.max_batch_size, :>, 0
  end
end
