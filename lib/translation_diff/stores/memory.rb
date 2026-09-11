# The default cache, a bounded in-process LRU. NOT thread-safe, deliberately -- set `redis_url` for that.
class TranslationDiff::Stores::Memory
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

  def write_multi(pairs)
    pairs.each { |key, value| write(key, value) }
  end

  private

  def touch(key)
    return nil unless @entries.key?(key)

    @entries[key] = @entries.delete(key)
  end
end

TranslationDiff::Stores.register(:memory, TranslationDiff::Stores::Memory)
