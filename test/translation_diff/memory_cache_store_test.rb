require "test_helper"
require "support/cache_store_contract"

class MemoryCacheStoreTest < Minitest::Test
  include CacheStoreContract

  attr_reader :store

  def setup
    @store = TranslationDiff::MemoryCacheStore.new(max_size: 3)
  end

  def test_it_evicts_the_oldest_entry_once_the_bound_is_reached
    %w[a b c d].each { |key| store.write(key, key) }

    assert_equal [nil, "b", "c", "d"], store.read_multi(%w[a b c d])
  end

  def test_reading_an_entry_makes_it_the_most_recently_used
    %w[a b c].each { |key| store.write(key, key) }
    store.read_multi(["a"])
    store.write("d", "d")

    assert_equal ["a", nil, "c", "d"], store.read_multi(%w[a b c d])
  end

  def test_rewriting_an_entry_makes_it_the_most_recently_used
    %w[a b c].each { |key| store.write(key, key) }
    store.write("a", "again")
    store.write("d", "d")

    assert_equal ["again", nil, "c", "d"], store.read_multi(%w[a b c d])
  end

  def test_build_takes_its_bound_from_the_configuration
    config = TranslationDiff::Configuration.new
    config.cache_max_size = 1

    built = TranslationDiff::MemoryCacheStore.build(config)
    built.write("a", "one")
    built.write("b", "two")

    assert_equal [nil, "two"], built.read_multi(%w[a b])
  end
end
