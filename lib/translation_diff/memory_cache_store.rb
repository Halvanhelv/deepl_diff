# frozen_string_literal: true

# The default cache: a bounded LRU in the current process, so the library
# works the moment it is required and without Redis running.
#
# Ruby hashes keep insertion order, so "least recently used" is delete and
# reinsert on every touch, and eviction is a shift of the first pair.
#
# NOT thread-safe, and deliberately so -- a lock here would be a tax on the
# single-threaded case to make the multi-threaded one merely less wrong. A
# process that needs a cache shared between threads or machines sets
# `redis_url` and gets TranslationDiff::RedisCacheStore instead.
class TranslationDiff::MemoryCacheStore
  def self.build(config) = new(max_size: config.cache_max_size)

  def initialize(max_size:)
    @max_size = max_size
    @entries = {}
  end

  def read_multi(keys)
    keys.map { |key| touch(key) }
  end

  def write(key, value)
    @entries.delete(key)
    @entries[key] = value
    @entries.shift while @entries.size > @max_size
    value
  end

  private

  def touch(key)
    return nil unless @entries.key?(key)

    @entries[key] = @entries.delete(key)
  end
end

TranslationDiff::Stores.register(:memory, TranslationDiff::MemoryCacheStore)
