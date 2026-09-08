# frozen_string_literal: true

require "test_helper"

# RedisRateLimiter requires "ratelimit" lazily, at the first check, so this
# file exercises the production integration against the real Ratelimit class
# rather than a stand-in. The stand-in this file used to define hid a real
# defect: the gem's signature is `add(subject, count)`, so `add(size)` was
# counting under a subject named after the character count while `exceeded?`
# read a subject nothing ever incremented -- the limit never fired.
require "ratelimit"

class RedisRateLimiterTest < Minitest::Test
  # An in-memory Redis server implementing exactly the commands ratelimit 1.1
  # issues, plus the two Lua scripts it loads (interpreted here rather than
  # run). No socket is opened; nothing here is a stub of the gem under test.
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

  # Ratelimit's own rule is `count >= threshold`, so the check that carries
  # the count over the line still passes and the next one raises.
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

  # Ratelimit buckets five seconds at a time, so the number of buckets its
  # count script sweeps is the interval divided by five -- exactly, since
  # both intervals here are multiples of five. That is the only observable
  # the interval has.
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

  # The gem used to name the bare `Ratelimit` constant, so an application
  # that had not installed it got a raw NameError rather than the "add this
  # gem" message the Redis path raises. The singleton `require` here is the
  # narrowest way to simulate the gem being absent: it shadows Kernel#require
  # for this one object only.
  def test_a_missing_ratelimit_gem_raises_a_translation_diff_error
    limiter = limiter(FakeRedisServer.new)
    limiter.define_singleton_method(:require) { |_name| raise LoadError }

    error = assert_raises(TranslationDiff::Error) { limiter.check(1) }

    assert_match(/`ratelimit` gem is not available/, error.message)
    assert_match(/Add `gem "ratelimit"`/, error.message)
  end

  private

  def limiter(server, **)
    TranslationDiff::RedisRateLimiter.new(FakeConnectionPool.new(server), **)
  end
end
