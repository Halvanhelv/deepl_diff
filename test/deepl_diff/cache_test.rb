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

  def setup
    @store = RecordingStore.new
    DeepLDiff.cache_store = @store
  end

  def teardown
    DeepLDiff.cache_store = nil
  end

  # Two providers writing to one store used to collide: switching DeepL for
  # another provider silently returned DeepL's translations.
  def test_the_provider_is_part_of_the_key
    key_for(provider: "deepl")
    key_for(provider: "google")

    refute_equal @store.keys[0], @store.keys[1]
  end

  # formality: :less used to share a key with the default, so whichever
  # translated first won.
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

  # "EN" and :en are the same language and used to produce two entries for
  # identical work.
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

  private

  def key_for(value: "text", from: :en, to: :ru, provider: "deepl", options: {})
    DeepLDiff::Cache.new(from, to, provider: provider, options: options)
                    .cached_and_missing([value])
  end
end
