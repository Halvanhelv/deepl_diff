# frozen_string_literal: true

require "test_helper"

class ProvidersTest < Minitest::Test
  # A provider defined entirely outside this library, to prove that adding a
  # translation service requires no change to lib/.
  class AcmeProvider
    def self.configuration_options = %i[acme_token]
    def self.build(config) = new(config.acme_token)

    attr_accessor :name

    def initialize(token)
      @token = token
    end

    def translate(texts, from:, to:, **_options)
      texts.map { |text| "#{@token}:#{from}-#{to}:#{text}" }
    end

    def max_request_size = 1_000
    def max_batch_size = 10
  end

  def setup
    TranslationDiff::Providers.register(:acme, AcmeProvider)
    @config = TranslationDiff::Configuration.new
    @config.acme_token = "T"
  end

  def test_registering_declares_the_providers_own_options_on_the_configuration
    assert_includes TranslationDiff::Configuration.options, :acme_token
  end

  def test_building_produces_a_working_provider
    provider = TranslationDiff::Providers.build(:acme, @config)

    assert_equal ["T:en-ru:hi"], provider.translate(["hi"], from: :en, to: :ru)
  end

  def test_the_registered_name_becomes_the_cache_key
    assert_equal "acme", TranslationDiff::Providers.build(:acme, @config).cache_key
  end

  def test_the_built_in_providers_are_registered
    assert TranslationDiff::Providers.registered?(:deepl)
    assert TranslationDiff::Providers.registered?(:null)
  end

  def test_null_keeps_its_own_cache_key
    assert_equal "null", TranslationDiff::Providers.build(:null, @config).cache_key
  end
end
