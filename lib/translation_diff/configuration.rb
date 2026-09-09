# frozen_string_literal: true

# Every setting this library has, declared in one place with its default.
#
#   TranslationDiff.configure do |config|
#     config.deepl_api_key = ENV["DEEPL_API_KEY"]
#     config.redis_url = ENV["REDIS_URL"]
#   end
#
# Options are declared with `option`, which generates a reader that falls back
# to the default and a writer that normalises a blank string to nil -- so an
# unset environment variable behaves as though the option was never touched.
#
# A default may be a literal or a callable. A callable is invoked on read, not
# at load time, so `-> { ENV["REDIS_URL"] }` reflects the environment when the
# value is needed rather than when this file was required.
#
# Provider-specific options such as `deepl_api_key` are NOT declared here.
# A provider declares its own and registers them through
# TranslationDiff::Providers.register, which keeps the core ignorant of any
# particular translation service.
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

    # Declares the options a provider needs, remembering which provider
    # declared each one. See ProviderOptionOwners (configuration/
    # provider_option_owners.rb) for the conflict rules and the
    # all-or-nothing guarantee.
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

  # Values are copied; memoised collaborators (`provider_instance`,
  # `cache_store`, `segmenter_instance`, `rate_limiter_instance` and
  # `redis_pool`) are deliberately not -- `copy` walks `self.class.options`
  # only, which never includes those readers' instance variables, so a copy
  # builds its own provider, store, rate limiter and connection pool from
  # its own values instead of inheriting the original's. This matters for
  # `rate_limiter_instance` in particular: a tenant context that sets its
  # own `cache_namespace` must not be rate-limited against its parent's
  # namespace just because the parent had already resolved a limiter before
  # the copy was made. An object the caller assigned is an option value and
  # is therefore shared -- which is correct: someone who hands us one
  # connection pool means one connection pool.
  def copy
    self.class.new.tap do |other|
      self.class.options.each do |key|
        other.instance_variable_set(:"@#{key}", instance_variable_get(:"@#{key}"))
      end
    end
  end

  # The provider actually used. `provider` holds what the caller set -- a
  # symbol or an object -- and this turns it into an instance once.
  def provider_instance
    @provider_instance ||= resolve(provider, TranslationDiff::Providers)
  end

  # `cache` unset means "choose for me": Redis when a URL is configured,
  # otherwise the in-process store, so the library works before anything is
  # running.
  def cache_store
    @cache_store ||= resolve(cache || (redis_url ? :redis : :memory), TranslationDiff::Stores)
  end

  def segmenter_instance
    @segmenter_instance ||= resolve(segmenter, TranslationDiff::Segmenters.registry)
  end

  # `rate_limiter` holds what the caller set -- an object, or nil -- exactly
  # like `provider`, `cache` and `segmenter` hold theirs. nil, not a null
  # object: Request checks for nil and skips the whole rate-limiting path,
  # which is the common case and should cost nothing.
  #
  # The assigned object when there is one; nil when no `rate_limit`
  # threshold was ever configured; a RedisRateLimiter built from this
  # config's own values otherwise. Memoised under its own instance
  # variable, like `provider_instance`, `cache_store` and
  # `segmenter_instance`, so a copy builds its own limiter from its own
  # settings instead of inheriting one built for a different config's
  # namespace or connection pool.
  def rate_limiter_instance
    return rate_limiter unless rate_limiter.nil?
    return nil if rate_limit.nil?

    @rate_limiter_instance ||= TranslationDiff::RedisRateLimiter.build(self)
  end

  # One pool for the cache store and the rate limiter both. Callers used to
  # build this themselves and pass it to each, keeping the namespaces in step
  # by hand.
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
