class TranslationDiff::RateLimiters::Redis
  DEFAULT_THRESHOLD = 8000
  DEFAULT_INTERVAL = 60
  DEFAULT_NAMESPACE = "translation-diff".freeze

  # This library limits the provider as a whole rather than per caller, so there is exactly one subject.
  SUBJECT = "call".freeze

  # An unset rate_limit must mean DEFAULT_THRESHOLD, not the nil that would override that keyword default.
  def self.build(config)
    options = { interval: config.rate_interval, namespace: config.cache_namespace }
    options[:threshold] = config.rate_limit unless config.rate_limit.nil?
    new(config.redis_pool, **options)
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
      exceeded = rate_limit.exceeded?(SUBJECT, threshold: threshold, interval: interval)
      raise TranslationDiff::RateLimitExceeded, exceeded_message if exceeded

      rate_limit.add(SUBJECT, size)
    end
  end

  private

  # Counts and settings, never a character of what was being translated.
  def exceeded_message
    "rate limit reached for #{namespace}: #{threshold} characters per #{interval} seconds"
  end

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

TranslationDiff::RateLimiters.register(:redis, TranslationDiff::RateLimiters::Redis)
