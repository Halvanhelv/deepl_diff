# frozen_string_literal: true

# The executable form of the adapter contract. Every adapter includes this
# and defines #adapter; anything that passes can be TranslationDiff.api.
module AdapterContract
  def test_translate_returns_one_string_per_input
    result = adapter.translate(%w[one two three], from: :en, to: :ru)

    assert_equal 3, result.size
    result.each { |value| assert_kind_of String, value }
  end

  def test_translate_preserves_order
    result = adapter.translate(%w[first second], from: :en, to: :ru)

    refute_equal result[0], result[1]
  end

  def test_translate_accepts_provider_options
    result = adapter.translate(%w[one], from: :en, to: :ru, formality: :less)

    assert_equal 1, result.size
  end

  def test_max_request_size_is_a_positive_integer
    assert_kind_of Integer, adapter.max_request_size
    assert_operator adapter.max_request_size, :>, 0
  end

  def test_max_batch_size_is_a_positive_integer
    assert_kind_of Integer, adapter.max_batch_size
    assert_operator adapter.max_batch_size, :>, 0
  end

  def test_cache_key_is_a_non_empty_string
    assert_kind_of String, adapter.cache_key
    refute_empty adapter.cache_key
  end
end
