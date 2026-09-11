require "test_helper"
require "support/env_stub"

class ConfigurationTest < Minitest::Test
  include EnvStub

  # A hand-written double for TranslationDiff::Registry: Minitest 6.0 dropped minitest/mock.
  # Duck-typed collaborators, deliberately inheriting nothing: the provider is the only tightened one.
  class FakeStore
    def read_multi(keys) = [nil] * keys.size
    def write(_key, value) = value
  end

  class FakeSegmenter
    def split_offsets(_text, **) = []
  end

  class FakeRateLimiter
    # The real limiter raises when the threshold is passed and returns nothing useful otherwise.
    def check(_size) = nil
  end

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

  def test_a_nil_cache_ttl_sticks_instead_of_falling_back_to_the_default
    @config.cache_ttl = nil

    assert_nil @config.cache_ttl
  end

  def test_a_zero_cache_ttl_also_means_never_expires
    @config.cache_ttl = 0

    assert_nil @config.cache_ttl
  end

  def test_a_negative_cache_ttl_also_means_never_expires
    @config.cache_ttl = -1

    assert_nil @config.cache_ttl
  end

  def test_cache_ttl_coerces_a_numeric_string_the_way_an_env_var_arrives
    @config.cache_ttl = "3600"

    assert_equal 3600, @config.cache_ttl
  end

  def test_a_coerced_non_positive_cache_ttl_string_also_means_never_expires
    @config.cache_ttl = "0"

    assert_nil @config.cache_ttl
  end

  def test_cache_ttl_refuses_a_non_numeric_string_with_a_clear_message
    error = assert_raises(TranslationDiff::Error) { @config.cache_ttl = "lots" }

    assert_match(/cache_ttl/, error.message)
  end

  def test_cache_prune_probability_coerces_a_numeric_string_the_way_an_env_var_arrives
    @config.cache_prune_probability = "0.5"

    assert_in_delta 0.5, @config.cache_prune_probability
  end

  def test_cache_prune_probability_refuses_a_non_numeric_string_with_a_clear_message
    error = assert_raises(TranslationDiff::Error) { @config.cache_prune_probability = "lots" }

    assert_match(/cache_prune_probability/, error.message)
  end

  def test_cache_prune_probability_refuses_a_value_above_one
    error = assert_raises(TranslationDiff::Error) { @config.cache_prune_probability = 2.0 }

    assert_match(/between 0 and 1/, error.message)
  end

  def test_cache_prune_probability_refuses_a_negative_value
    error = assert_raises(TranslationDiff::Error) { @config.cache_prune_probability = -1 }

    assert_match(/between 0 and 1/, error.message)
  end

  def test_cache_prune_probability_accepts_the_boundary_values
    @config.cache_prune_probability = 0

    assert_in_delta 0.0, @config.cache_prune_probability

    @config.cache_prune_probability = 1

    assert_in_delta 1.0, @config.cache_prune_probability
  end

  def test_cache_namespace_longer_than_64_characters_is_refused_at_configure_time
    error = assert_raises(TranslationDiff::Error) { @config.cache_namespace = "n" * 65 }

    assert_match(/64/, error.message)
  end

  def test_cache_namespace_at_the_64_character_limit_is_accepted
    @config.cache_namespace = "n" * 64

    assert_equal "n" * 64, @config.cache_namespace
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
    # test_flag is registered here purely to exercise `option`; it is not a production option.
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

  # Stand-ins for two provider classes, to distinguish redeclaring from a name collision.
  class AcmeOptionOwner
    def self.configuration_options = %i[acme_api_key]
  end

  class RivalOptionOwner
    def self.configuration_options = %i[contested_key]
  end

  def test_register_provider_options_adds_readers_and_writers
    # acme_api_key is registered here purely to exercise register_provider_options; not a production option.
    TranslationDiff::Configuration.register_provider_options(%i[acme_api_key], AcmeOptionOwner)
    @config.acme_api_key = "secret"

    assert_equal "secret", @config.acme_api_key
    assert_includes TranslationDiff::Configuration.options, :acme_api_key
  end

  # A double `require` and a Rails development reload both re-run registration; neither is a conflict.
  def test_the_same_provider_may_redeclare_its_own_options
    TranslationDiff::Configuration.register_provider_options(%i[acme_repeat_key], AcmeOptionOwner)
    TranslationDiff::Configuration.register_provider_options(%i[acme_repeat_key], AcmeOptionOwner)

    assert_includes TranslationDiff::Configuration.options, :acme_repeat_key
  end

  # Without this, `option` returns early and two providers silently share one accessor.
  def test_a_different_provider_declaring_a_declared_option_raises
    TranslationDiff::Configuration.register_provider_options(%i[contested_key], AcmeOptionOwner)

    error = assert_raises(TranslationDiff::Error) do
      TranslationDiff::Configuration.register_provider_options(%i[contested_key], RivalOptionOwner)
    end

    assert_match(/contested_key/, error.message)
    assert_match(/AcmeOptionOwner/, error.message)
    assert_match(/RivalOptionOwner/, error.message)
  end

  # A subclass wanting its parent's options is the one case where sharing the accessor is correct.
  class AcmeSubclassOwner < AcmeOptionOwner; end

  def test_a_subclass_of_the_declaring_provider_may_redeclare_its_options
    TranslationDiff::Configuration.register_provider_options(%i[acme_subclass_key], AcmeOptionOwner)
    TranslationDiff::Configuration.register_provider_options(%i[acme_subclass_key], AcmeSubclassOwner)

    assert_includes TranslationDiff::Configuration.options, :acme_subclass_key
  end

  # The guard only relaxes for an actual inheritance relationship; an unrelated class is still refused.
  def test_an_unrelated_class_claiming_a_subclassable_providers_option_still_raises
    TranslationDiff::Configuration.register_provider_options(%i[acme_unrelated_key], AcmeOptionOwner)

    error = assert_raises(TranslationDiff::Error) do
      TranslationDiff::Configuration.register_provider_options(%i[acme_unrelated_key], RivalOptionOwner)
    end

    assert_match(/acme_unrelated_key/, error.message)
  end

  # Conflicts on its *second* option, once its first (fresh_option) has already been checked.
  class IntruderOptionOwner
    def self.configuration_options = %i[fresh_option owned_by_acme]
  end

  # Used to declare ownership key by key, leaving the first option owned by a class that failed to register.
  def test_a_conflict_on_a_later_option_leaves_no_partial_state
    TranslationDiff::Configuration.register_provider_options(%i[owned_by_acme], AcmeOptionOwner)

    assert_raises(TranslationDiff::Error) do
      keys = IntruderOptionOwner.configuration_options
      TranslationDiff::Configuration.register_provider_options(keys, IntruderOptionOwner)
    end

    refute_includes TranslationDiff::Configuration.options, :fresh_option

    # If the failed attempt had already claimed :fresh_option, this would raise, blaming the wrong provider.
    TranslationDiff::Configuration.register_provider_options(%i[fresh_option], RivalOptionOwner)

    assert_includes TranslationDiff::Configuration.options, :fresh_option
  end

  # A provider needing no default keeps the bare-symbol form; one needing a default declares `key => default`.
  class DefaultingOptionOwner
    def self.configuration_options
      [:defaulting_bare, { defaulting_keyed: -> { ENV.fetch("DEFAULTING_TEST_VAR", nil) } }]
    end
  end

  def test_a_provider_declares_bare_symbols_and_defaults_in_one_list
    TranslationDiff::Configuration.register_provider_options(
      DefaultingOptionOwner.configuration_options, DefaultingOptionOwner
    )

    assert_includes TranslationDiff::Configuration.options, :defaulting_bare
    assert_includes TranslationDiff::Configuration.options, :defaulting_keyed
    assert_nil TranslationDiff::Configuration.new.defaulting_bare
  end

  # Evaluated on read, not at load: an application that sets the variable after requiring us still gets it.
  def test_a_declared_callable_default_is_evaluated_on_every_read
    TranslationDiff::Configuration.register_provider_options(
      DefaultingOptionOwner.configuration_options, DefaultingOptionOwner
    )

    with_env("DEFAULTING_TEST_VAR" => "from-the-environment") do
      assert_equal "from-the-environment", TranslationDiff::Configuration.new.defaulting_keyed
    end
  end

  def test_an_assigned_value_wins_over_a_declared_default
    TranslationDiff::Configuration.register_provider_options(
      DefaultingOptionOwner.configuration_options, DefaultingOptionOwner
    )
    config = TranslationDiff::Configuration.new
    config.defaulting_keyed = "assigned"

    with_env("DEFAULTING_TEST_VAR" => "from-the-environment") do
      assert_equal "assigned", config.defaulting_keyed
    end
  end

  # The blank rule the writer already applies: a variable exported empty means unset, not an empty credential.
  def test_a_blank_default_reads_as_unset
    TranslationDiff::Configuration.register_provider_options(
      DefaultingOptionOwner.configuration_options, DefaultingOptionOwner
    )

    with_env("DEFAULTING_TEST_VAR" => "   ") do
      assert_nil TranslationDiff::Configuration.new.defaulting_keyed
    end
  end

  class KeyedConflictOwner
    def self.configuration_options = [:keyed_fresh_option, { owned_by_acme: -> { "x" } }]
  end

  # Ownership is claimed for every key however it was written, so a keyed clash still leaves no partial state.
  def test_a_conflict_on_a_keyed_option_leaves_no_partial_state
    TranslationDiff::Configuration.register_provider_options(%i[owned_by_acme], AcmeOptionOwner)

    assert_raises(TranslationDiff::Error) do
      TranslationDiff::Configuration.register_provider_options(
        KeyedConflictOwner.configuration_options, KeyedConflictOwner
      )
    end

    refute_includes TranslationDiff::Configuration.options, :keyed_fresh_option
  end

  def test_registering_an_option_twice_does_not_clobber_the_first_default
    # shared_option is not a production option; mutating class-level state with it is harmless.
    TranslationDiff::Configuration.option(:shared_option, "first")
    TranslationDiff::Configuration.option(:shared_option, "second")

    assert_equal "first", TranslationDiff::Configuration.new.shared_option
  end

  # Providers.register refuses a class that skips the base class; assigning an object bypassed that entirely.
  def test_an_assigned_provider_object_that_is_not_a_provider_is_refused
    @config.provider = Object.new

    error = assert_raises(TranslationDiff::InvalidProviderError) { @config.provider_instance }

    assert_match(/TranslationDiff::Provider/, error.message)
  end

  def test_an_assigned_provider_object_that_is_a_provider_is_used_as_is
    provider = TranslationDiff::Providers::Null.new(TranslationDiff::Configuration.new)
    @config.provider = provider

    assert_same provider, @config.provider_instance
  end

  # Only the provider gained a base class; these three are still genuinely duck-typed.
  def test_the_other_extension_points_stay_duck_typed
    @config.cache = FakeStore.new
    @config.segmenter = FakeSegmenter.new
    @config.rate_limiter = FakeRateLimiter.new

    assert_instance_of FakeStore, @config.cache_store
    assert_instance_of FakeSegmenter, @config.segmenter_instance
    assert_instance_of FakeRateLimiter, @config.rate_limiter_instance
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
    assert_nil @config.rate_limiter_instance
  end

  def test_a_rate_limit_builds_a_redis_rate_limiter
    @config.rate_limit = 100
    @config.redis_url = "redis://localhost:6379"

    assert_instance_of TranslationDiff::RedisRateLimiter, @config.rate_limiter_instance
  end

  def test_a_symbol_rate_limiter_resolves_through_the_registry
    @config.rate_limit = 100
    @config.rate_limiter = :active_record

    assert_instance_of TranslationDiff::ActiveRecordRateLimiter, @config.rate_limiter_instance
  end

  def test_a_string_rate_limiter_resolves_through_the_registry
    @config.rate_limit = 100
    @config.rate_limiter = "active_record"

    assert_instance_of TranslationDiff::ActiveRecordRateLimiter, @config.rate_limiter_instance
  end

  def test_an_unknown_rate_limiter_name_raises_listing_what_is_registered
    @config.rate_limit = 100
    @config.rate_limiter = :nonsense

    error = assert_raises(TranslationDiff::Error) { @config.rate_limiter_instance }

    assert_includes error.message, "rate limiter"
    assert_includes error.message, "redis"
  end

  def test_an_assigned_rate_limiter_object_wins_over_every_value
    limiter = Object.new
    @config.rate_limiter = limiter

    assert_same limiter, @config.rate_limiter_instance
  end

  def test_an_assigned_rate_limiter_object_is_used_even_without_a_rate_limit
    limiter = Object.new
    @config.rate_limiter = limiter

    assert_nil @config.rate_limit
    assert_same limiter, @config.rate_limiter_instance
  end

  def test_the_default_rate_limiter_is_memoised
    @config.rate_limit = 100

    assert_same @config.rate_limiter_instance, @config.rate_limiter_instance
  end

  # Used to be broken: a copy inherited an already-built limiter and rate-limited a tenant against its parent's.
  def test_copy_does_not_share_a_built_default_rate_limiter
    @config.rate_limit = 100
    original_limiter = @config.rate_limiter_instance

    refute_same original_limiter, @config.copy.rate_limiter_instance
  end

  # An assigned object is an option value, and `copy` carries option values over on purpose.
  def test_copy_shares_an_assigned_rate_limiter_object
    limiter = Object.new
    @config.rate_limiter = limiter

    assert_same limiter, @config.copy.rate_limiter_instance
  end

  # The regression this whole area was fixed for.
  def test_a_copy_that_changes_its_namespace_gets_a_rate_limiter_using_that_namespace
    @config.rate_limit = 100
    @config.redis_url = "redis://localhost:6379"
    @config.cache_namespace = "parent-ns"
    @config.rate_limiter_instance # resolve/build on the parent before copying

    copy = @config.copy
    copy.cache_namespace = "tenant-ns"

    assert_equal "tenant-ns", copy.rate_limiter_instance.send(:namespace)
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

  def test_opaque_elements_defaults_to_script_style_pre_and_code
    assert_equal %i[script style pre code], @config.opaque_elements
  end

  def test_opaque_elements_is_a_plain_setting_an_application_can_replace
    @config.opaque_elements = %i[script style kbd samp]

    assert_equal %i[script style kbd samp], @config.opaque_elements
  end

  def test_the_redis_pool_is_built_once_and_shared
    @config.redis_url = "redis://localhost:6379"
    @config.rate_limit = 100

    assert_same @config.cache_store.send(:connection_pool), @config.redis_pool
    assert_same @config.rate_limiter_instance.send(:connection_pool), @config.redis_pool
  end

  def test_copy_does_not_share_memoised_collaborators
    @config.cache = :memory
    original_store = @config.cache_store

    refute_same original_store, @config.copy.cache_store
  end

  # A real registered provider, to prove invalidation reaches provider_instance through a declared option too.
  class DoubleProvider < TranslationDiff::Provider
    def self.configuration_options = %i[double_provider_key]

    def translate(request) = TranslationDiff::Translation::Response.build(request: request, texts: request.texts)
  end

  def test_changing_the_provider_rebuilds_the_memoised_instance
    @config.provider = :null
    first = @config.provider_instance

    @config.provider = :null

    refute_same first, @config.provider_instance
  end

  def test_changing_an_option_a_provider_declared_rebuilds_the_provider_instance
    TranslationDiff::Providers.register(:double_provider, DoubleProvider)
    @config.provider = :double_provider
    @config.double_provider_key = "first"
    first = @config.provider_instance

    @config.double_provider_key = "second"

    refute_same first, @config.provider_instance
  end

  def test_changing_the_logger_leaves_the_redis_pool_in_place
    @config.redis_url = "redis://localhost:6379"
    pool = @config.redis_pool

    @config.logger = Object.new

    assert_same pool, @config.redis_pool
  end

  def test_changing_the_cache_namespace_rebuilds_the_cache_store
    original = @config.cache_store

    @config.cache_namespace = "a-different-namespace"

    refute_same original, @config.cache_store
  end

  def test_changing_the_redis_url_rebuilds_the_pool_the_store_and_the_rate_limiter
    @config.redis_url = "redis://localhost:6379"
    @config.rate_limit = 100
    pool = @config.redis_pool
    store = @config.cache_store
    limiter = @config.rate_limiter_instance

    @config.redis_url = "redis://localhost:6380"

    refute_same pool, @config.redis_pool
    refute_same store, @config.cache_store
    refute_same limiter, @config.rate_limiter_instance
  end

  def test_changing_the_rate_limit_leaves_the_cache_store_in_place
    store = @config.cache_store

    @config.rate_limit = 50

    assert_same store, @config.cache_store
  end

  def test_changing_the_segmenter_rebuilds_the_memoised_instance
    first = @config.segmenter_instance

    @config.segmenter = :simple

    refute_same first, @config.segmenter_instance
  end

  def test_an_unclassified_option_invalidates_nothing
    @config.provider = :null
    provider = @config.provider_instance
    store = @config.cache_store

    @config.max_retries = 1

    assert_same provider, @config.provider_instance
    assert_same store, @config.cache_store
  end
end
