# frozen_string_literal: true

require "test_helper"

class ProviderTest < Minitest::Test
  class Bare < TranslationDiff::Provider
  end

  class Demanding < TranslationDiff::Provider
    def self.configuration_options = %i[demanding_key demanding_secret demanding_region]
    def self.configuration_requirements = %i[demanding_key demanding_secret]
  end

  def setup
    TranslationDiff::Configuration.register_provider_options(
      Demanding.configuration_options, Demanding
    )
    @config = TranslationDiff::Configuration.new
  end

  def test_a_provider_without_requirements_builds
    assert_instance_of Bare, Bare.new(@config)
  end

  # The old behaviour was a DeepL:: error raised from inside a vendor SDK, or
  # `ArgumentError, "project_id is missing"` from another. Neither named the
  # option a caller of THIS library has to set.
  def test_it_names_every_missing_option_at_once
    error = assert_raises(TranslationDiff::ConfigurationError) { Demanding.new(@config) }

    assert_match(/demanding_key/, error.message)
    assert_match(/demanding_secret/, error.message)
    assert_match(/TranslationDiff.configure/, error.message)
  end

  # An option that is declared but not required must not appear in the error.
  def test_it_does_not_demand_optional_options
    @config.demanding_key = "k"
    @config.demanding_secret = "s"

    assert_instance_of Demanding, Demanding.new(@config)
  end

  def test_translate_raises_until_a_subclass_implements_it
    request = TranslationDiff::Translation::Request.new(texts: %w[one], from: "en", to: "ru")

    assert_raises(NotImplementedError) { Bare.new(@config).translate(request) }
  end

  def test_detect_raises_until_a_subclass_implements_it
    assert_raises(NotImplementedError) { Bare.new(@config).detect("etwas") }
  end

  # cache_key is a segment of every cache key this provider reads or writes.
  # A quietly empty one would let two providers share a namespace and serve
  # one service's translations for another.
  def test_cache_key_is_the_registered_name
    provider = Bare.new(@config)
    provider.name = :bare

    assert_equal "bare", provider.cache_key
  end

  def test_cache_key_raises_when_the_provider_was_never_stamped
    error = assert_raises(TranslationDiff::Error) { Bare.new(@config).cache_key }

    assert_match(/registry/, error.message)
  end

  def test_the_default_capabilities_are_conservative
    capabilities = TranslationDiff::Provider.capabilities

    refute_predicate capabilities, :html?
    refute_predicate capabilities, :notranslate?
    refute_predicate capabilities, :detects_language?
    refute_predicate capabilities, :reports_billing?
  end
end
