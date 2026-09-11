# The full option table: every setting Configuration exposes, its default, and what it invalidates.
# Lives apart from Configuration itself so the class that implements the behaviour isn't measured by
# a list that only grows -- this module is documentation as much as code, read it as a reference.
module TranslationDiff::Configuration::OptionTable
  # [key, default, the memoised reader(s) it invalidates -- nil means it invalidates nothing]
  TABLE = [
    [:provider, :deepl, :provider_instance], # rubocop:disable Style/SymbolArray -- stays [key, default, invalidates]
    [:cache, nil, :cache_store],
    [:cache_ttl, 604_800, :cache_store],
    # Also the rate limiter's own namespace (RedisRateLimiter, ActiveRecordRateLimiter both read it).
    [:cache_namespace, "translation-diff", %i[cache_store rate_limiter_instance]],
    [:cache_max_size, 1_000, :cache_store],
    [:cache_table_name, "translation_diff_translations", :cache_store],
    [:rate_limit_table_name, "translation_diff_rate_limits", :rate_limiter_instance],
    [:active_record_base, nil, %i[cache_store rate_limiter_instance]],
    [:cache_prune_probability, 0.0, :cache_store],
    [:redis_url, -> { ENV.fetch("REDIS_URL", nil) }, %i[redis_pool cache_store rate_limiter_instance]],
    [:redis_pool_size, 5, %i[redis_pool cache_store rate_limiter_instance]],
    [:redis_pool_timeout, 5, %i[redis_pool cache_store rate_limiter_instance]],
    [:rate_limit, nil, :rate_limiter_instance],
    [:rate_interval, 60, :rate_limiter_instance],
    [:rate_limiter, nil, :rate_limiter_instance],
    [:segmenter, :pragmatic, :segmenter_instance], # rubocop:disable Style/SymbolArray
    [:opaque_elements, %i[script style pre code], nil],
    [:instrumenter, nil, nil],
    [:logger, nil, nil],
    # HTTPProvider#connection memoises a Faraday connection built from these three, and the provider itself
    # is memoised too, so a change here has to reach provider_instance or it never reaches the connection.
    [:open_timeout, 5, :provider_instance],
    [:timeout, 30, :provider_instance],
    [:max_retries, 3, :provider_instance],
    [:validate_languages, true, nil]
  ].freeze

  def self.declare_on(configuration_class)
    TABLE.each { |key, default, invalidates| configuration_class.option(key, default, invalidates: invalidates) }
  end
end
