require "test_helper"
require "support/cache_store_contract"
require "support/batching_cache_store_contract"

# Nested inside the real Redis class, requiring it explicitly, so this never races Configuration's lazy require.
require "redis"

class Redis::Namespace
  def initialize(namespace, redis:)
    @namespace = namespace
    @redis = redis
  end

  def mget(*keys)
    @redis.mget(*keys.map { |key| "#{@namespace}:#{key}" })
  end

  def setex(key, timeout, value)
    @redis.setex("#{@namespace}:#{key}", timeout, value)
  end

  def set(key, value)
    @redis.set("#{@namespace}:#{key}", value)
  end

  def pipelined
    @redis.pipelined { |pipeline| yield self.class.new(@namespace, redis: pipeline) }
  end
end

class RedisStoreTest < Minitest::Test
  include CacheStoreContract
  include BatchingCacheStoreContract

  # `values`, when given, forces #mget to return it regardless of keys asked, to inspect keys without real storage.
  class FakeRedis
    attr_reader :calls

    def initialize(values = nil)
      @values = values
      @entries = {}
      @calls = []
    end

    def mget(*keys)
      @calls << [:mget, keys]
      return @values if @values

      keys.map { |key| @entries[key] }
    end

    def setex(key, timeout, value)
      @calls << [:setex, key, timeout, value]
      @entries[key] = value
      "OK"
    end

    def set(key, value)
      @calls << [:set, key, value]
      @entries[key] = value
      "OK"
    end

    def pipelined
      @calls << [:pipelined]
      yield self
    end
  end

  attr_reader :store

  def setup
    @store = build_store(FakeRedis.new)
  end

  def test_read_multi_namespaces_the_keys
    redis = FakeRedis.new(%w[one two])

    assert_equal %w[one two], build_store(redis).read_multi(%w[a b])
    assert_equal [[:mget, %w[translation-diff:a translation-diff:b]]], redis.calls
  end

  def test_write_expires_after_a_week_by_default
    redis = FakeRedis.new

    build_store(redis).write("a", "b")

    assert_equal [[:setex, "translation-diff:a", 604_800, "b"]], redis.calls
  end

  def test_write_honours_a_custom_timeout_and_namespace
    redis = FakeRedis.new

    build_store(redis, timeout: 60, namespace: "t").write("a", "b")

    assert_equal [[:setex, "t:a", 60, "b"]], redis.calls
  end

  def test_write_multi_sends_one_pipeline_rather_than_one_round_trip_per_key
    redis = FakeRedis.new

    build_store(redis).write_multi([%w[a one], %w[b two]])

    assert_equal [[:pipelined],
                  [:setex, "translation-diff:a", 604_800, "one"],
                  [:setex, "translation-diff:b", 604_800, "two"]], redis.calls
  end

  def test_write_multi_of_no_pairs_never_opens_a_pipeline
    redis = FakeRedis.new

    build_store(redis).write_multi([])

    assert_empty redis.calls
  end

  # The regression this closes: `setex(key, nil, value)` raised TypeError on every write against the default store.
  def test_write_with_a_nil_timeout_never_expires
    redis = FakeRedis.new

    build_store(redis, timeout: nil).write("a", "b")

    assert_equal [[:set, "translation-diff:a", "b"]], redis.calls
  end

  def test_write_with_a_zero_timeout_never_expires
    redis = FakeRedis.new

    build_store(redis, timeout: 0).write("a", "b")

    assert_equal [[:set, "translation-diff:a", "b"]], redis.calls
  end

  def test_write_with_a_negative_timeout_never_expires
    redis = FakeRedis.new

    build_store(redis, timeout: -1).write("a", "b")

    assert_equal [[:set, "translation-diff:a", "b"]], redis.calls
  end

  def test_write_multi_with_a_nil_timeout_never_expires
    redis = FakeRedis.new

    build_store(redis, timeout: nil).write_multi([%w[a one], %w[b two]])

    assert_equal [[:pipelined],
                  [:set, "translation-diff:a", "one"],
                  [:set, "translation-diff:b", "two"]], redis.calls
  end

  private

  def build_store(redis, **)
    TranslationDiff::Stores::Redis.new(FakeConnectionPool.new(redis), **)
  end
end
