require "test_helper"
require "support/rate_limiter_contract"

# A prior stand-in here hid a real defect: `add(size)` counted under the wrong subject and the limit never fired.
require "ratelimit"

class RedisRateLimiterTest < Minitest::Test
  include RateLimiterContract

  # An in-memory Redis server implementing exactly the commands ratelimit 1.1 issues; no socket is opened.
  class FakeRedisServer
    attr_reader :hashes, :expiries, :count_spans

    def initialize
      @hashes = Hash.new { |hash, key| hash[key] = {} }
      @expiries = {}
      @scripts = {}
      @count_spans = []
    end

    def script(operation, source)
      raise ArgumentError, "unexpected SCRIPT #{operation.inspect}" unless operation == :load

      sha = "sha-#{@scripts.size}"
      @scripts[sha] = source
      sha
    end

    def evalsha(sha, keys, argv)
      @scripts.fetch(sha) == ::Ratelimit::COUNT_LUA_SCRIPT ? count(keys.first, argv) : expire_buckets(keys.first, argv)
    end

    def multi
      @queued = []
      yield self
      @queued.tap { @queued = nil }
    end

    def hincrby(key, field, count)
      @hashes[key][field.to_s] = @hashes[key][field.to_s].to_i + count
      @queued << @hashes[key][field.to_s]
    end

    def expire(key, seconds)
      @expiries[key] = seconds
      @queued << true
    end

    # Total counted per subject key, which is what the limiter is for.
    def totals = @hashes.transform_values { |buckets| buckets.values.sum }

    private

    def count(subject, argv)
      oldest, current = argv.map(&:to_i)
      @count_spans << (current - oldest)
      ((oldest + 1)..current).sum { |bucket| @hashes[subject][bucket.to_s].to_i }
    end

    def expire_buckets(subject, argv)
      @hashes[subject].delete_if { |bucket, _| bucket.to_i < argv.first.to_i }
      nil
    end
  end

  def test_check_counts_the_characters_it_was_given_under_the_namespace
    server = FakeRedisServer.new

    limiter(server).check(120)
    limiter(server).check(30)

    assert_equal({ "ratelimit:translation-diff:call" => 150 }, server.totals)
  end

  def test_check_counts_under_a_custom_namespace
    server = FakeRedisServer.new

    limiter(server, namespace: "tenant-42").check(7)

    assert_equal({ "ratelimit:tenant-42:call" => 7 }, server.totals)
  end

  # Ratelimit's own rule is `count >= threshold`, so the check that carries the count over the line still passes.
  def test_check_raises_once_the_threshold_is_passed
    server = FakeRedisServer.new

    limiter(server, threshold: 100).check(100)

    assert_raises(TranslationDiff::RedisRateLimiter::RateLimitExceeded) do
      limiter(server, threshold: 100).check(1)
    end
    assert_equal({ "ratelimit:translation-diff:call" => 100 }, server.totals)
  end

  def test_check_uses_the_default_threshold
    server = FakeRedisServer.new

    limiter(server).check(TranslationDiff::RedisRateLimiter::DEFAULT_THRESHOLD)

    assert_raises(TranslationDiff::RedisRateLimiter::RateLimitExceeded) { limiter(server).check(1) }
  end

  # Ratelimit buckets five seconds at a time, so buckets swept is the interval divided by five.
  def test_check_looks_back_over_the_default_interval
    server = FakeRedisServer.new

    limiter(server).check(1)

    assert_equal [TranslationDiff::RedisRateLimiter::DEFAULT_INTERVAL / 5], server.count_spans
  end

  def test_check_looks_back_over_a_custom_interval
    server = FakeRedisServer.new

    limiter(server, interval: 600).check(1)

    assert_equal [120], server.count_spans
  end

  # The other half of a window: what fell out of it stops counting, or a limiter never recovers.
  def test_a_bucket_older_than_the_interval_is_not_counted
    server = FakeRedisServer.new
    stale = (Time.now.to_i / 5) - (TranslationDiff::RedisRateLimiter::DEFAULT_INTERVAL / 5) - 1
    server.hashes["ratelimit:translation-diff:call"][stale.to_s] = 10_000

    limiter(server, threshold: 100).check(1)
  end

  # Naming the bare `Ratelimit` constant used to raise a raw NameError instead of this gem's own message.
  def test_a_missing_ratelimit_gem_raises_a_translation_diff_error
    limiter = limiter(FakeRedisServer.new)
    limiter.define_singleton_method(:require) { |_name| raise LoadError }

    error = assert_raises(TranslationDiff::Error) { limiter.check(1) }

    assert_match(/`ratelimit` gem is not available/, error.message)
    assert_match(/Add `gem "ratelimit"`/, error.message)
  end

  # Setting only `rate_limiter`, the config option that turns this limiter on, must not crash every call.
  def test_build_falls_back_to_the_default_threshold_when_rate_limit_is_unset
    server = FakeRedisServer.new
    config = TranslationDiff::Configuration.new
    config.rate_limiter = :redis
    config.instance_variable_set(:@redis_pool, FakeConnectionPool.new(server))

    built = TranslationDiff::RedisRateLimiter.build(config)

    assert_equal TranslationDiff::RedisRateLimiter::DEFAULT_THRESHOLD, built.send(:threshold)
    built.check(1)
  end

  # The settings screen that found this: changing cache_namespace must move the limiter, not just the cache.
  def test_changing_the_cache_namespace_moves_the_limiter_to_the_new_redis_namespace
    server = FakeRedisServer.new
    config = TranslationDiff::Configuration.new
    config.rate_limit = 100
    config.instance_variable_set(:@redis_pool, FakeConnectionPool.new(server))

    config.rate_limiter_instance.check(10)
    config.cache_namespace = "tenant-42"
    config.rate_limiter_instance.check(7)

    assert_equal({ "ratelimit:translation-diff:call" => 10, "ratelimit:tenant-42:call" => 7 }, server.totals)
  end

  private

  def limiter(server, **)
    TranslationDiff::RedisRateLimiter.new(FakeConnectionPool.new(server), **)
  end

  def rate_limit_exceeded_error = TranslationDiff::RedisRateLimiter::RateLimitExceeded

  def build_limiter(threshold:, interval:)
    @contract_server ||= FakeRedisServer.new
    limiter(@contract_server, threshold: threshold, interval: interval)
  end
end
