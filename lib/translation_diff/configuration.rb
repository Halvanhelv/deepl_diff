# Every declared setting in one place; callable defaults are invoked on read, not at load time.
class TranslationDiff::Configuration
  class << self
    # `invalidates:` names the memoised reader(s) this option feeds; a writer clears exactly those ivars.
    # An option that names none -- logger, instrumenter, the timeouts -- clears nothing, which is also
    # what an option nobody classifies does: invalidation is opt-in, never a guess from the option's name.
    def option(key, default = nil, invalidates: nil)
      key = key.to_sym
      return if options.include?(key)

      define_option_accessors(key, Array(invalidates))
      defaults[key] = default
      options << key
    end

    # See ProviderOptionOwners for the conflict rules and the all-or-nothing guarantee. Every provider
    # option invalidates provider_instance, whatever it is named -- the registry, not a remembered list,
    # is what makes the set known.
    def register_provider_options(declared, provider)
      declared = normalise_declarations(declared)
      provider_option_owners.claim(declared.keys, provider)
      declared.each { |key, default| option(key, default, invalidates: :provider_instance) }
    end

    def options = @options ||= []
    def defaults = @defaults ||= {}

    private

    # The writer clears exactly the memos this option was declared to invalidate; the reader defers to `read`.
    # A write that leaves the raw value unchanged clears none of them -- a per-request write of the same
    # tenant must not rebuild a cache store that was already warm.
    def define_option_accessors(key, memos)
      ivar = :"@#{key}"
      define_method(:"#{key}=") do |value|
        value = nil if value.is_a?(String) && value.strip.empty?
        next if instance_variable_get(ivar) == value

        instance_variable_set(ivar, value)
        memos.each { |memo| instance_variable_set(:"@#{memo}", nil) }
      end
      define_method(key) { read(key) }
    end

    # `:key` declares an option with no default; `{ key => default }` declares one, and a callable is read lazily.
    def normalise_declarations(declared)
      entries = declared.is_a?(Hash) ? [declared] : Array(declared)

      entries.each_with_object({}) do |entry, result|
        entry.is_a?(Hash) ? result.merge!(entry.transform_keys(&:to_sym)) : result[entry.to_sym] = nil
      end
    end

    def provider_option_owners = @provider_option_owners ||= ProviderOptionOwners.new
  end

  # Required here, not centrally: the modules they define nest under this class, which must exist first.
  require "translation_diff/configuration/option_table"
  TranslationDiff::Configuration::OptionTable.declare_on(self)

  require "translation_diff/configuration/cache_ttl_option"
  require "translation_diff/configuration/cache_guard_options"
  prepend TranslationDiff::Configuration::CacheTtlOption
  prepend TranslationDiff::Configuration::CacheGuardOptions

  # Credentials are filtered by name; everything else is shown, or an inspect is one nobody reads.
  def inspect = "#<#{self.class.name} #{TranslationDiff::Redaction.render(self).join(' ')}>"

  # Memoised collaborators aren't copied, or a tenant's own cache_namespace leaks its parent's rate limiter.
  def copy
    self.class.new.tap do |other|
      self.class.options.each do |key|
        other.instance_variable_set(:"@#{key}", instance_variable_get(:"@#{key}"))
      end
    end
  end

  # Guarded, unlike cache/segmenter/rate_limiter: only the provider gained a base class to check against.
  def provider_instance
    @provider_instance ||=
      TranslationDiff::Providers.ensure_provider!(resolve(provider, TranslationDiff::Providers))
  end

  # Unset `cache` means Redis when a URL is configured, otherwise in-process -- works before anything runs.
  def cache_store
    @cache_store ||= resolve(cache || (redis_url ? :redis : :memory), TranslationDiff::Stores)
  end

  def segmenter_instance
    @segmenter_instance ||= resolve(segmenter, TranslationDiff::Segmenters.registry)
  end

  # nil, not a null object: Dispatcher#throttle checks for nil and skips rate-limiting -- costs nothing normally.
  def rate_limiter_instance
    return nil if rate_limiter.nil? && rate_limit.nil?

    @rate_limiter_instance ||= resolve(rate_limiter || :redis, TranslationDiff::RateLimiters)
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

  # A default is resolved on every read, and a blank one is unset -- the rule the writer already applies.
  def read(key)
    value = instance_variable_get(:"@#{key}")
    return value unless value.nil?

    default = self.class.defaults[key]
    blank_to_nil(default.respond_to?(:call) ? default.call : default)
  end

  def blank_to_nil(value) = value.is_a?(String) && value.strip.empty? ? nil : value

  # The symbol-or-object rule, implemented once for all three extension points.
  def resolve(value, registry)
    value.is_a?(Symbol) || value.is_a?(String) ? registry.build(value, self) : value
  end
end
