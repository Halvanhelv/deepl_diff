require "test_helper"
require "support/provider_contract"
require "support/http_provider_contract"
require "support/stubbed_provider"
require "support/env_stub"
require "faraday"

class DeepLProviderTest < Minitest::Test
  include ProviderContract
  include HTTPProviderContract
  include StubbedProvider
  include EnvStub

  # A real response body, captured from api-free.deepl.com on 2026-09-09.
  TRANSLATE_BODY = {
    "translations" => [
      { "detected_source_language" => "EN", "text" => "один", "billed_characters" => 3 },
      { "detected_source_language" => "EN", "text" => "два", "billed_characters" => 3 }
    ]
  }.freeze

  attr_reader :config

  def setup
    TranslationDiff.reset!
    @config = TranslationDiff::Configuration.new
    @config.deepl_api_key = "test-key:fx"
  end

  def provider_class = TranslationDiff::Providers::DeepL

  # Left nil, `body:` echoes back whatever texts were sent, so ProviderContract's count check never trips.
  def provider(body: nil, status: 200, headers: {})
    stub_provider(route: "/v2/translate", body: body || method(:echo_translations),
                  status: status, headers: headers, name: :deepl)
  end

  # deepl-rb read DEEPL_AUTH_KEY on our behalf; an app that set it and configured nothing kept working.
  def test_the_deepl_auth_key_environment_variable_supplies_an_unset_key
    with_env("DEEPL_AUTH_KEY" => "env-key:fx") do
      assert_equal "env-key:fx", TranslationDiff::Configuration.new.deepl_api_key
    end
  end

  # The default is a callable, so setting the variable after this file was required still works.
  def test_the_environment_is_read_on_use_not_at_load_time
    built = TranslationDiff::Configuration.new

    with_env("DEEPL_AUTH_KEY" => "set-after-the-fact") do
      assert_equal "set-after-the-fact", built.deepl_api_key
    end
  end

  def test_an_explicitly_configured_key_wins_over_the_environment
    with_env("DEEPL_AUTH_KEY" => "env-key") do
      assert_equal "test-key:fx", config.deepl_api_key
    end
  end

  def test_a_blank_environment_variable_is_not_a_key
    with_env("DEEPL_AUTH_KEY" => "  ") do
      assert_nil TranslationDiff::Configuration.new.deepl_api_key
    end
  end

  # The scenario: ensure_configured! raised ConfigurationError at boot for an app that only set the variable.
  def test_the_environment_variable_satisfies_the_configuration_requirement
    with_env("DEEPL_AUTH_KEY" => "env-key") do
      assert_instance_of TranslationDiff::Providers::DeepL,
                         TranslationDiff::Providers::DeepL.new(TranslationDiff::Configuration.new)
    end
  end

  # DeepL documents upper-case codes; a caller writing Google-style lower case must still work.
  def test_it_upcases_a_bare_language_code_whichever_casing_the_caller_used
    provider.translate(translation_request(%w[one], from: "en", to: "ru"))

    assert_equal "EN", sent["source_lang"]
    assert_equal "RU", sent["target_lang"]
  end

  # The casing of a script or region subtag is its own; upcasing "pt-BR" corrupts it.
  def test_it_leaves_a_subtagged_code_untouched
    provider.translate(translation_request(%w[one], from: "zh-Hans", to: "pt-BR"))

    assert_equal "zh-Hans", sent["source_lang"]
    assert_equal "pt-BR", sent["target_lang"]
  end

  def test_a_free_key_selects_the_free_host
    assert_equal "https://api-free.deepl.com", TranslationDiff::Providers::DeepL.new(config).api_base
  end

  def test_a_paid_key_selects_the_paid_host
    config.deepl_api_key = "test-key"

    assert_equal "https://api.deepl.com", TranslationDiff::Providers::DeepL.new(config).api_base
  end

  def test_the_api_base_option_overrides_both
    config.deepl_api_base = "https://deepl.internal"

    assert_equal "https://deepl.internal", TranslationDiff::Providers::DeepL.new(config).api_base
  end

  def test_it_authenticates_with_the_deepl_scheme
    assert_equal "DeepL-Auth-Key test-key:fx",
                 TranslationDiff::Providers::DeepL.new(config).headers["Authorization"]
  end

  def test_a_missing_key_is_named_before_any_request
    config.deepl_api_key = nil

    error = assert_raises(TranslationDiff::ConfigurationError) do
      TranslationDiff::Providers::DeepL.new(config)
    end

    assert_match(/deepl_api_key/, error.message)
  end

  def test_it_sends_the_texts_and_the_language_pair
    provider.translate(translation_request(%w[one two]))

    assert_equal %w[one two], sent["text"]
    assert_equal "EN", sent["source_lang"]
    assert_equal "RU", sent["target_lang"]
  end

  # DeepL wants upper-case language codes; a caller writing "en" must work.
  def test_it_upcases_the_language_codes
    provider.translate(translation_request(%w[one two], from: "en", to: "ru"))

    assert_equal "EN", sent["source_lang"]
    assert_equal "RU", sent["target_lang"]
  end

  def test_it_omits_the_source_language_when_none_was_given
    provider.translate(translation_request(%w[one two], from: nil))

    refute sent.key?("source_lang")
  end

  # DeepL honours class="notranslate" only under HTML tag handling; otherwise content translates, tags survive.
  def test_it_asks_for_html_tag_handling
    provider.translate(translation_request(%w[one two]))

    assert_equal "html", sent["tag_handling"]
    assert_equal "v2", sent["tag_handling_version"]
  end

  def test_a_caller_option_overrides_a_default
    provider.translate(translation_request(%w[one two], tag_handling: "xml", formality: "less"))

    assert_equal "xml", sent["tag_handling"]
    assert_equal "less", sent["formality"]
  end

  def test_it_returns_the_translations_in_order
    response = provider(body: TRANSLATE_BODY).translate(translation_request(%w[one two]))

    assert_equal %w[один два], response.texts
  end

  def test_it_reports_the_detected_source_and_the_billed_characters
    response = provider(body: TRANSLATE_BODY).translate(translation_request(%w[one two], from: nil))

    assert_equal "en", response.detected_source
    assert_equal 6, response.usage.billed_characters
  end

  # nil means "the provider did not say"; a reported 0 is a claim, and mapping it to nil erased one.
  def test_a_reported_zero_is_zero_not_unknown
    body = { "translations" => [{ "text" => "один", "billed_characters" => 0 },
                                { "text" => "два", "billed_characters" => 0 }] }
    response = provider(body: body).translate(translation_request(%w[one two]))

    assert_equal 0, response.usage.billed_characters
  end

  def test_billed_characters_is_nil_when_no_translation_reported_it
    body = { "translations" => [{ "text" => "один" }, { "text" => "два" }] }
    response = provider(body: body).translate(translation_request(%w[one two]))

    assert_nil response.usage.billed_characters
  end

  def test_a_short_response_raises_rather_than_shifting_nils_into_the_results
    short = { "translations" => [{ "text" => "один" }] }

    assert_raises(TranslationDiff::ResponseError) do
      provider(body: short).translate(translation_request(%w[one two]))
    end
  end

  # DeepL has no detection endpoint; it detects by translating a sample and reading the reported source.
  def test_detect_returns_the_language_deepl_reports
    assert_equal "en", provider.detect("something")
  end

  def test_its_batch_limit_is_deepls_documented_fifty
    assert_equal 50, TranslationDiff::Providers::DeepL.capabilities.max_batch_size
  end

  def test_it_claims_html_and_notranslate
    capabilities = TranslationDiff::Providers::DeepL.capabilities

    assert_predicate capabilities, :html?
    assert_predicate capabilities, :notranslate?
    assert_predicate capabilities, :detects_language?
    assert_predicate capabilities, :reports_billing?
  end

  private

  def echo_translations(env)
    texts = JSON.parse(env.body)["text"]
    { "translations" => texts.map { |t| { "text" => t, "detected_source_language" => "EN" } } }
  end
end
