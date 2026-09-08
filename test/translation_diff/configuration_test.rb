# frozen_string_literal: true

require "test_helper"

class ConfigurationTest < Minitest::Test
  # A hand-written double for TranslationDiff::Registry: this project's
  # Minitest (6.0) dropped minitest/mock, so there is no Minitest::Mock here.
  ResolvingRegistry = Struct.new(:answer) do
    attr_reader :asked

    def build(name, config)
      @asked = [name, config]
      answer
    end
  end

  def setup
    @config = TranslationDiff::Configuration.new
  end

  def test_an_option_returns_its_default_until_it_is_assigned
    assert_equal 604_800, @config.cache_ttl

    @config.cache_ttl = 60

    assert_equal 60, @config.cache_ttl
  end

  def test_a_callable_default_is_evaluated_on_every_read_not_at_load_time
    original = ENV.fetch("REDIS_URL", nil)
    ENV["REDIS_URL"] = "redis://first"

    assert_equal "redis://first", @config.redis_url

    ENV["REDIS_URL"] = "redis://second"

    assert_equal "redis://second", @config.redis_url
  ensure
    ENV["REDIS_URL"] = original
  end

  def test_assigning_a_blank_string_stores_nil_so_an_unset_env_var_behaves_as_unset
    @config.cache_namespace = "   "

    assert_equal "translation-diff", @config.cache_namespace
  end

  def test_assigning_false_is_kept_and_not_treated_as_unset
    # test_flag is registered here purely to exercise `option`; it is not a
    # production option and mutating class-level state with it is harmless.
    TranslationDiff::Configuration.option(:test_flag, true)
    @config.test_flag = false

    refute @config.test_flag
  end

  def test_copy_carries_values_and_leaves_the_original_alone
    @config.cache_ttl = 60

    copy = @config.copy
    copy.cache_ttl = 120

    assert_equal 60, @config.cache_ttl
    assert_equal 120, copy.cache_ttl
  end

  def test_register_provider_options_adds_readers_and_writers
    # acme_api_key is registered here purely to exercise
    # register_provider_options; it is not a production option and mutating
    # class-level state with it is harmless.
    TranslationDiff::Configuration.register_provider_options(%i[acme_api_key])
    @config.acme_api_key = "secret"

    assert_equal "secret", @config.acme_api_key
    assert_includes TranslationDiff::Configuration.options, :acme_api_key
  end

  def test_registering_an_option_twice_does_not_clobber_the_first_default
    # shared_option is not a production option; mutating class-level state
    # with it is harmless.
    TranslationDiff::Configuration.option(:shared_option, "first")
    TranslationDiff::Configuration.option(:shared_option, "second")

    assert_equal "first", TranslationDiff::Configuration.new.shared_option
  end

  def test_resolve_builds_from_a_registry_for_a_symbol
    built = Object.new
    registry = ResolvingRegistry.new(built)

    assert_same built, @config.send(:resolve, :thing, registry)
    assert_equal [:thing, @config], registry.asked
  end

  def test_resolve_returns_an_object_untouched
    object = Object.new
    registry = Object.new # would raise NoMethodError if touched

    assert_same object, @config.send(:resolve, object, registry)
  end

  def test_cache_store_defaults_to_memory_when_no_redis_url_is_set
    original = ENV.fetch("REDIS_URL", nil)
    ENV["REDIS_URL"] = nil

    assert_instance_of TranslationDiff::MemoryCacheStore, @config.cache_store
  ensure
    ENV["REDIS_URL"] = original
  end

  def test_cache_store_defaults_to_redis_when_a_redis_url_is_set
    @config.redis_url = "redis://localhost:6379"

    assert_instance_of TranslationDiff::RedisCacheStore, @config.cache_store
  end

  def test_an_assigned_cache_object_wins_over_every_value
    store = Object.new
    @config.cache = store
    @config.redis_url = "redis://localhost:6379"

    assert_same store, @config.cache_store
  end

  def test_the_cache_store_is_memoised
    assert_same @config.cache_store, @config.cache_store
  end

  def test_there_is_no_rate_limiter_unless_a_rate_limit_is_set
    assert_nil @config.rate_limiter
  end

  def test_a_rate_limit_builds_a_redis_rate_limiter
    @config.rate_limit = 100
    @config.redis_url = "redis://localhost:6379"

    assert_instance_of TranslationDiff::RedisRateLimiter, @config.rate_limiter
  end

  def test_an_assigned_rate_limiter_object_wins_over_every_value
    limiter = Object.new
    @config.rate_limiter = limiter

    assert_same limiter, @config.rate_limiter
  end

  def test_an_assigned_rate_limiter_object_is_used_even_without_a_rate_limit
    limiter = Object.new
    @config.rate_limiter = limiter

    assert_nil @config.rate_limit
    assert_same limiter, @config.rate_limiter
  end

  def test_the_default_rate_limiter_is_memoised
    @config.rate_limit = 100

    assert_same @config.rate_limiter, @config.rate_limiter
  end

  # Unlike `cache_store`/`provider_instance`/`segmenter_instance`, a copy
  # does inherit an already-built default rate limiter: `rate_limiter` has
  # no separate resolved-value reader of its own, so there is only the one
  # instance variable for `copy` to carry over.
  def test_copy_shares_a_built_default_rate_limiter
    @config.rate_limit = 100
    original_limiter = @config.rate_limiter

    assert_same original_limiter, @config.copy.rate_limiter
  end

  def test_copy_shares_an_assigned_rate_limiter_object
    limiter = Object.new
    @config.rate_limiter = limiter

    assert_same limiter, @config.copy.rate_limiter
  end

  def test_segmenter_instance_resolves_the_default_symbol
    assert_instance_of TranslationDiff::Segmenters::Pragmatic, @config.segmenter_instance
  end

  def test_segmenter_instance_resolves_a_named_alternative
    @config.segmenter = :simple

    assert_instance_of TranslationDiff::Segmenters::Simple, @config.segmenter_instance
  end

  def test_an_assigned_segmenter_object_passes_through_untouched
    segmenter = Object.new
    @config.segmenter = segmenter

    assert_same segmenter, @config.segmenter_instance
  end

  def test_an_unknown_segmenter_name_raises_listing_what_is_registered
    @config.segmenter = :nonsense

    error = assert_raises(TranslationDiff::Error) { @config.segmenter_instance }

    assert_includes error.message, "segmenter"
    assert_includes error.message, "pragmatic"
  end

  def test_the_redis_pool_is_built_once_and_shared
    @config.redis_url = "redis://localhost:6379"
    @config.rate_limit = 100

    assert_same @config.cache_store.send(:connection_pool), @config.redis_pool
    assert_same @config.rate_limiter.send(:connection_pool), @config.redis_pool
  end

  def test_copy_does_not_share_memoised_collaborators
    @config.cache = :memory
    original_store = @config.cache_store

    refute_same original_store, @config.copy.cache_store
  end
end
