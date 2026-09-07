# frozen_string_literal: true

require "test_helper"

# The gem does not depend on the ratelimit gem -- it only constructs whatever
# Ratelimit resolves to. This stand-in records onto the connection it is given,
# which is the only handle the test has on the object built inside #check.
class Ratelimit
  def initialize(namespace, redis:)
    @namespace = namespace
    @redis = redis
  end

  def exceeded?(subject, threshold:, interval:)
    @redis.checks << [@namespace, subject, threshold, interval]
    @redis.exceeded
  end

  def add(size)
    @redis.added << size
  end
end

class RedisRateLimiterTest < Minitest::Test
  class FakeRedis
    attr_reader :checks, :added, :exceeded

    def initialize(exceeded: false)
      @exceeded = exceeded
      @checks = []
      @added = []
    end
  end

  def test_check_uses_the_default_threshold_and_interval
    redis = FakeRedis.new

    limiter(redis).check(120)

    assert_equal [["deepl-diff", "call", 8000, 60]], redis.checks
    assert_equal [120], redis.added
  end

  # Regression test: these used to be positional, so the documented keyword
  # call silently fell back to the defaults.
  def test_check_honours_a_custom_threshold_interval_and_namespace
    redis = FakeRedis.new

    limiter(redis, threshold: 999, interval: 7, namespace: "t").check(1)

    assert_equal [["t", "call", 999, 7]], redis.checks
  end

  def test_check_raises_once_the_threshold_is_passed
    redis = FakeRedis.new(exceeded: true)

    assert_raises(DeepLDiff::RedisRateLimiter::RateLimitExceeded) do
      limiter(redis).check(1)
    end
    assert_empty redis.added
  end

  private

  def limiter(redis, **)
    DeepLDiff::RedisRateLimiter.new(FakeConnectionPool.new(redis), **)
  end
end
