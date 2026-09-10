class TranslationDiff::RedisRateLimiter
  class RateLimitExceeded < TranslationDiff::Error; end

  DEFAULT_THRESHOLD = 8000
  DEFAULT_INTERVAL = 60
  DEFAULT_NAMESPACE = "translation-diff".freeze

  # This library limits the provider as a whole rather than per caller, so there is exactly one subject.
  SUBJECT = "call".freeze

  def self.build(config)
    new(config.redis_pool,
        threshold: config.rate_limit,
        interval: config.rate_interval,
        namespace: config.cache_namespace)
  end

  # `connection_pool` is duck-typed to #with; neither connection_pool nor ratelimit is a hard dependency.
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

  # Required at first check, not load time; naming the bare constant instead would raise a raw NameError.
  def ratelimit_class
    require "ratelimit"
    ::Ratelimit
  rescue LoadError
    raise TranslationDiff::Error,
          "a rate limit was configured but the `ratelimit` gem is not available. " \
          'Add `gem "ratelimit"` to your Gemfile.'
  end
end

TranslationDiff::RateLimiters.register(:redis, TranslationDiff::RedisRateLimiter)
