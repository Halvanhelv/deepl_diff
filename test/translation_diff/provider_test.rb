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

  class Upcasing < TranslationDiff::Provider
    def self.language_case = :upcase
  end

  # The rule lived in google.rb and nowhere else; four providers shipped without it.
  def test_a_bare_code_is_cased_the_way_the_vendor_documents_it
    downcasing = Bare.new(@config)
    upcasing = Upcasing.new(@config)

    assert_equal "ru", downcasing.language("RU")
    assert_equal "ru", downcasing.language(:ru)
    assert_equal "RU", upcasing.language("ru")
    assert_equal "RU", upcasing.language(:RU)
  end

  # A script or region subtag has its own casing; a blanket transform corrupts it.
  def test_a_subtagged_code_passes_through_untouched
    downcasing = Bare.new(@config)
    upcasing = Upcasing.new(@config)

    %w[zh-Hans pt-BR EN-GB sr-Latn-RS].each do |code|
      assert_equal code, downcasing.language(code)
      assert_equal code, upcasing.language(code)
    end
  end

  # nil so a provider can leave the field out of the payload entirely rather than sending "".
  def test_an_absent_code_is_nil
    assert_nil Bare.new(@config).language(nil)
    assert_nil Bare.new(@config).language("")
  end

  def test_providers_downcase_unless_they_say_otherwise
    assert_equal :downcase, TranslationDiff::Provider.language_case
    assert_equal :upcase, TranslationDiff::Providers::DeepL.language_case

    %w[Google Azure ModernMT LibreTranslate Amazon].each do |name|
      assert_equal :downcase, TranslationDiff::Providers.const_get(name).language_case
    end
  end

  def test_a_provider_without_requirements_builds
    assert_instance_of Bare, Bare.new(@config)
  end

  # The old behaviour raised a vendor SDK's own error, which never named the option this library needs set.
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

  # A quietly empty cache_key would let two providers share a namespace and serve the wrong translations.
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
