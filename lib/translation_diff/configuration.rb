# frozen_string_literal: true

# Every declared setting in one place; callable defaults are invoked on read, not at load time.
class TranslationDiff::Configuration
  class << self
    def option(key, default = nil)
      key = key.to_sym
      return if options.include?(key)

      define_method(:"#{key}=") do |value|
        value = nil if value.is_a?(String) && value.strip.empty?
        instance_variable_set(:"@#{key}", value)
      end
      define_method(key) { read(key) }

      defaults[key] = default
      options << key
    end

    # See ProviderOptionOwners for the conflict rules and the all-or-nothing guarantee.
    def register_provider_options(keys, provider)
      keys = Array(keys).map(&:to_sym)
      provider_option_owners.claim(keys, provider)
      keys.each { |key| option(key) }
    end

    def options = @options ||= []
    def defaults = @defaults ||= {}

    private

    def provider_option_owners = @provider_option_owners ||= ProviderOptionOwners.new
  end

  option :provider, :deepl
  option :cache, nil
  option :cache_ttl, 604_800
  option :cache_namespace, "translation-diff"
  option :cache_max_size, 1_000
  option :redis_url, -> { ENV.fetch("REDIS_URL", nil) }
  option :redis_pool_size, 5
  option :redis_pool_timeout, 5
  option :rate_limit, nil
  option :rate_interval, 60
  option :rate_limiter, nil
  option :segmenter, :pragmatic
  option :instrumenter, nil
  option :logger, nil
  option :open_timeout, 5
  option :timeout, 30
  option :max_retries, 3

  # Memoised collaborators aren't copied, or a tenant's own cache_namespace leaks its parent's rate limiter.
  def copy
    self.class.new.tap do |other|
      self.class.options.each do |key|
        other.instance_variable_set(:"@#{key}", instance_variable_get(:"@#{key}"))
      end
    end
  end

  def provider_instance
    @provider_instance ||= resolve(provider, TranslationDiff::Providers)
  end

  # Unset `cache` means Redis when a URL is configured, otherwise in-process -- works before anything runs.
  def cache_store
    @cache_store ||= resolve(cache || (redis_url ? :redis : :memory), TranslationDiff::Stores)
  end

  def segmenter_instance
    @segmenter_instance ||= resolve(segmenter, TranslationDiff::Segmenters.registry)
  end

  # nil, not a null object: Request checks for nil and skips rate-limiting entirely -- costs nothing normally.
  def rate_limiter_instance
    return rate_limiter unless rate_limiter.nil?
    return nil if rate_limit.nil?

    @rate_limiter_instance ||= TranslationDiff::RedisRateLimiter.build(self)
  end

  # One pool shared by the cache store and the rate limiter; callers used to build and pass it by hand.
  def redis_pool
    @redis_pool ||= build_redis_pool
  end

  private

  def build_redis_pool
    require "connection_pool"
    require "redis"
    ConnectionPool.new(size: redis_pool_size, timeout: redis_pool_timeout) do
      Redis.new(url: redis_url)
    end
  rescue LoadError
    raise TranslationDiff::Error,
          "a Redis-backed cache or rate limiter was requested but the gems are not " \
          'available. Add `gem "redis"`, `gem "connection_pool"` and ' \
          '`gem "redis-namespace"` to your Gemfile.'
  end

  def read(key)
    value = instance_variable_get(:"@#{key}")
    return value unless value.nil?

    default = self.class.defaults[key]
    default.respond_to?(:call) ? default.call : default
  end

  # The symbol-or-object rule, implemented once for all three extension points.
  def resolve(value, registry)
    value.is_a?(Symbol) || value.is_a?(String) ? registry.build(value, self) : value
  end
end
