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
end
