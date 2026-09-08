# frozen_string_literal: true

# The executable form of the provider contract. Every provider includes this
# and defines #provider; anything that passes can be registered with
# TranslationDiff::Providers.register and reached through TranslationDiff.translate.
module ProviderContract
  def test_translate_returns_one_string_per_input
    result = provider.translate(%w[one two three], from: :en, to: :ru)

    assert_equal 3, result.size
    result.each { |value| assert_kind_of String, value }
  end

  def test_translate_preserves_order
    texts = %w[first second third]
    individually = texts.map { |text| provider.translate([text], from: :en, to: :ru).first }
    batched = provider.translate(texts, from: :en, to: :ru)

    assert_equal 3, batched.size
    assert_equal individually, batched
  end

  def test_translate_accepts_provider_options
    result = provider.translate(%w[one], from: :en, to: :ru, formality: :less)

    assert_equal 1, result.size
  end

  def test_max_request_size_is_a_positive_integer
    assert_kind_of Integer, provider.max_request_size
    assert_operator provider.max_request_size, :>, 0
  end

  def test_max_batch_size_is_a_positive_integer
    assert_kind_of Integer, provider.max_batch_size
    assert_operator provider.max_batch_size, :>, 0
  end
end
