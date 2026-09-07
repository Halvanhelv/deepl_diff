# frozen_string_literal: true

require "test_helper"

# The gem depends on neither redis nor redis-namespace -- it just calls into
# whatever the application supplies. This stand-in applies the namespace the
# way redis-namespace does, so the keys reaching Redis can be asserted on.
module Redis; end

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
  class FakeRedis
    attr_reader :calls

    def initialize(values = [])
      @values = values
      @calls = []
    end

    def mget(*keys)
      @calls << [:mget, keys]
      @values
    end

    def setex(key, timeout, value)
      @calls << [:setex, key, timeout, value]
      "OK"
    end
  end

  def test_read_multi_namespaces_the_keys
    redis = FakeRedis.new(%w[one two])

    assert_equal %w[one two], store(redis).read_multi(%w[a b])
    assert_equal [[:mget, %w[deepl-diff:a deepl-diff:b]]], redis.calls
  end

  def test_write_expires_after_a_week_by_default
    redis = FakeRedis.new

    store(redis).write("a", "b")

    assert_equal [[:setex, "deepl-diff:a", 604_800, "b"]], redis.calls
  end

  def test_write_honours_a_custom_timeout_and_namespace
    redis = FakeRedis.new

    store(redis, timeout: 60, namespace: "t").write("a", "b")

    assert_equal [[:setex, "t:a", 60, "b"]], redis.calls
  end

  private

  def store(redis, **)
    DeepLDiff::RedisCacheStore.new(FakeConnectionPool.new(redis), **)
  end
end
