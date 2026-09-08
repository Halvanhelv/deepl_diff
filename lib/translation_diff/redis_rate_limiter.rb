# frozen_string_literal: true

class TranslationDiff::RedisRateLimiter
  class RateLimitExceeded < TranslationDiff::Error; end

  DEFAULT_THRESHOLD = 8000
  DEFAULT_INTERVAL = 60
  DEFAULT_NAMESPACE = "translation-diff"

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
    connection_pool.with do |redis|
      rate_limit = Ratelimit.new(namespace, redis: redis)
      raise RateLimitExceeded if rate_limit.exceeded?("call", threshold: threshold, interval: interval)

      rate_limit.add size
    end
  end

  private

  attr_reader :connection_pool, :threshold, :interval, :namespace
end
