# frozen_string_literal: true

require "test_helper"
require "support/cache_store_contract"

# The gem depends on neither redis nor redis-namespace at runtime -- it just
# calls into whatever the application supplies. This stand-in applies the
# namespace the way redis-namespace does, so the keys reaching Redis can be
# asserted on.
#
# TranslationDiff::Configuration#redis_pool requires the real "redis" gem
# lazily, at call time, so whether ::Redis is already defined when this file
# runs depends on test order -- Minitest randomises it. Requiring it
# explicitly here, and nesting this stand-in inside the real class instead of
# declaring a fake top-level `Redis` module, means this file never collides
# with -- or races -- that real constant.
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
end

class RedisCacheStoreTest < Minitest::Test
  include CacheStoreContract

  # `values`, when given, forces every #mget to return it regardless of the
  # keys asked for -- what the namespacing tests below use to inspect the
  # keys reaching Redis without needing real storage behind them. Without
  # it, #mget and #setex behave like a real key/value store, which is what
  # the shared CacheStoreContract needs.
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

  private

  def build_store(redis, **)
    TranslationDiff::RedisCacheStore.new(FakeConnectionPool.new(redis), **)
  end
end
