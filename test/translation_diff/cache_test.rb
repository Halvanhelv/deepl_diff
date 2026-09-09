# frozen_string_literal: true

require "test_helper"

class CacheTest < Minitest::Test
  class RecordingStore
    attr_reader :keys

    def initialize
      @keys = []
    end

    def read_multi(keys)
      @keys.concat(keys)
      [nil] * keys.size
    end

    def write(_key, value)
      value
    end
  end

  # Answers with fixed results regardless of keys asked, to pin the positional contract.
  class PositionalStore
    def initialize(responses)
      @responses = responses
    end

    def read_multi(_keys)
      @responses
    end
  end

  def setup
    @store = RecordingStore.new
  end

  # Two providers writing to one store used to collide, silently returning DeepL's translations for another.
  def test_the_provider_is_part_of_the_key
    key_for(provider: "deepl")
    key_for(provider: "google")

    refute_equal @store.keys[0], @store.keys[1]
  end

  # formality: :less used to share a key with the default, so whichever translated first won.
  def test_the_provider_options_are_part_of_the_key
    key_for(options: {})
    key_for(options: { formality: :less })

    refute_equal @store.keys[0], @store.keys[1]
  end

  def test_the_options_digest_is_order_independent
    key_for(options: { a: 1, b: 2 })
    key_for(options: { b: 2, a: 1 })

    assert_equal @store.keys[0], @store.keys[1]
  end

  # "EN" and :en are the same language and used to produce two entries for identical work.
  def test_the_language_codes_are_normalised
    key_for(from: "EN", to: "RU")
    key_for(from: :en, to: :ru)

    assert_equal @store.keys[0], @store.keys[1]
  end

  def test_leading_and_trailing_space_does_not_change_the_key
    key_for(value: "text")
    key_for(value: "  text  ")

    assert_equal @store.keys[0], @store.keys[1]
  end

  # nil and "" are different values; #to_s would collide them.
  def test_nil_and_empty_string_option_values_produce_different_keys
    key_for(options: { a: nil })
    key_for(options: { a: "" })

    refute_equal @store.keys[0], @store.keys[1]
  end

  # Exercises the Array branch of #canonical, which no other test in this file reaches.
  def test_an_array_option_value_is_part_of_the_digest
    key_for(options: { glossary_ids: %w[a b] })
    key_for(options: { glossary_ids: %w[a c] })

    refute_equal @store.keys[0], @store.keys[1]
  end

  # An option value with no stable serialisation must not silently produce an unreproducible cache key.
  def test_an_unsupported_option_value_raises
    assert_raises(TranslationDiff::Cache::Error) { key_for(options: { a: Object.new }) }
  end

  # Trusts the store to return results in key order; a `WHERE key IN (...)` store will not.
  def test_cached_and_missing_pairs_results_positionally
    store = PositionalStore.new(["cached one", nil, "cached three"])

    cached, missing = TranslationDiff::Cache.new(:en, :ru, provider: "deepl", store: store)
                                            .cached_and_missing(%w[one two three])

    assert_equal ["cached one", nil, "cached three"], cached
    assert_equal ["two"], missing
  end

  private

  def key_for(value: "text", from: :en, to: :ru, provider: "deepl", options: {})
    TranslationDiff::Cache.new(from, to, provider: provider, store: @store, options: options)
                          .cached_and_missing([value])
  end
end
