# frozen_string_literal: true

class TranslationDiff::RedisRateLimiter
  class RateLimitExceeded < TranslationDiff::Error; end

  DEFAULT_THRESHOLD = 8000
  DEFAULT_INTERVAL = 60
  DEFAULT_NAMESPACE = "translation-diff"

  # Ratelimit counts per subject. This library limits the provider as a
  # whole rather than per caller, so there is exactly one subject and it
  # only has to be stable.
  SUBJECT = "call"

  def self.build(config)
    new(config.redis_pool,
        threshold: config.rate_limit,
        interval: config.rate_interval,
        namespace: config.cache_namespace)
  end

  # `connection_pool` is anything answering to #with, and what it yields is
  # anything Ratelimit accepts. Neither gem is a dependency of this one.
  def initialize(connection_pool,
                 threshold: DEFAULT_THRESHOLD,
                 interval: DEFAULT_INTERVAL,
                 namespace: DEFAULT_NAMESPACE)
    @connection_pool = connection_pool
    @threshold = threshold
    @interval = interval
    @namespace = namespace
  end

  def check(size)
    limiter_class = ratelimit_class

    connection_pool.with do |redis|
      rate_limit = limiter_class.new(namespace, redis: redis)
      raise RateLimitExceeded if rate_limit.exceeded?(SUBJECT, threshold: threshold, interval: interval)

      rate_limit.add(SUBJECT, size)
    end
  end

  private

  attr_reader :connection_pool, :threshold, :interval, :namespace

  # `ratelimit` is not a dependency of this gem, so it is required here, at
  # the first check, rather than at load time -- an application that
  # configures no `rate_limit` never needs it installed. Naming the bare
  # constant instead surfaced its absence as a raw NameError; this raises the
  # same "add this gem" TranslationDiff::Error the Redis path already does.
  def ratelimit_class
    require "ratelimit"
    ::Ratelimit
  rescue LoadError
    raise TranslationDiff::Error,
          "a rate limit was configured but the `ratelimit` gem is not available. " \
          'Add `gem "ratelimit"` to your Gemfile.'
  end
end
