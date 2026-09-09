# frozen_string_literal: true

require "test_helper"
require "support/provider_contract"
require "support/http_provider_contract"
require "support/stubbed_provider"
require "faraday"
require "cgi"

class AzureProviderTest < Minitest::Test
  include ProviderContract
  include HTTPProviderContract
  include StubbedProvider

  # No Azure key was available: shaped from Microsoft's v3 "Translate" reference (read 2026-09-09), not observed.
  BODY = [
    { "detectedLanguage" => { "language" => "en", "score" => 1.0 },
      "translations" => [{ "text" => "один", "to" => "ru" }] },
    { "detectedLanguage" => { "language" => "en", "score" => 1.0 },
      "translations" => [{ "text" => "два", "to" => "ru" }] }
  ].freeze

  attr_reader :config

  def setup
    TranslationDiff.reset!
    @config = TranslationDiff::Configuration.new
    @config.azure_api_key = "test-key"
  end

  def provider_class = TranslationDiff::Providers::Azure

  # Left nil, `body:` echoes back whatever texts were sent, so ProviderContract's count check never trips.
  def provider(body: nil, status: 200, headers: {})
    stub_provider(route: "/translate", body: body || method(:echo_translations),
                  status: status, headers: headers, name: :azure)
  end

  def test_the_default_api_base_is_the_documented_host
    assert_equal "https://api.cognitive.microsofttranslator.com",
                 TranslationDiff::Providers::Azure.new(config).api_base
  end

  def test_the_api_base_option_overrides_the_default
    config.azure_api_base = "https://azure.internal"

    assert_equal "https://azure.internal", TranslationDiff::Providers::Azure.new(config).api_base
  end

  def test_it_sends_the_key_in_the_documented_header
    assert_equal "test-key",
                 TranslationDiff::Providers::Azure.new(config).headers["Ocp-Apim-Subscription-Key"]
  end

  # A single-service key needs no region and a multi-service one does.
  def test_the_region_header_appears_only_when_configured
    refute TranslationDiff::Providers::Azure.new(config).headers.key?("Ocp-Apim-Subscription-Region")

    config.azure_region = "westeurope"

    assert_equal "westeurope",
                 TranslationDiff::Providers::Azure.new(config).headers["Ocp-Apim-Subscription-Region"]
  end

  def test_a_missing_key_is_named_before_any_request
    config.azure_api_key = nil

    error = assert_raises(TranslationDiff::ConfigurationError) do
      TranslationDiff::Providers::Azure.new(config)
    end

    assert_match(/azure_api_key/, error.message)
  end

  def test_the_languages_travel_in_the_query_string_not_the_body
    provider.translate(translation_request(%w[one two]))

    assert_equal ["3.0"], query["api-version"]
    assert_equal ["en"], query["from"]
    assert_equal ["ru"], query["to"]
  end

  def test_it_omits_from_when_none_was_given
    provider.translate(translation_request(%w[one], from: nil))

    refute query.key?("from")
  end

  # The body is an array of objects with a capital-T Text key.
  def test_it_wraps_each_text_in_the_documented_object
    provider.translate(translation_request(%w[one two]))

    assert_equal [{ "Text" => "one" }, { "Text" => "two" }], sent
  end

  def test_it_asks_for_html
    provider.translate(translation_request(%w[one]))

    assert_equal ["html"], query["textType"]
  end

  def test_it_flattens_one_translation_per_input
    response = provider(body: BODY).translate(translation_request(%w[one two]))

    assert_equal %w[один два], response.texts
    assert_equal "en", response.detected_source
  end

  def test_it_reads_the_billed_characters_from_the_metered_usage_header
    response = provider(body: BODY, headers: { "X-metered-usage" => "6" })
               .translate(translation_request(%w[one two]))

    assert_equal 6, response.usage.billed_characters
  end

  # Absent, the header must yield nil rather than 0 -- 0 is a false claim about billing, not "unknown".
  def test_billed_characters_is_nil_when_the_header_is_absent
    response = provider(body: BODY).translate(translation_request(%w[one two]))

    assert_nil response.usage.billed_characters
  end

  def test_a_short_response_raises_rather_than_shifting_nils_into_the_results
    short = [BODY.first]

    assert_raises(TranslationDiff::ResponseError) do
      provider(body: short).translate(translation_request(%w[one two]))
    end
  end

  def test_detect_returns_the_language_azure_reports
    detector = stub_provider(route: "/detect", body: [{ "language" => "en", "score" => 1.0 }],
                             name: :azure)

    assert_equal "en", detector.detect("something")
  end

  def test_its_limits_are_azures_documented_ones
    capabilities = TranslationDiff::Providers::Azure.capabilities

    assert_equal 1_000, capabilities.max_batch_size
    assert_equal 50_000, capabilities.max_request_size
    assert_equal 50_000, capabilities.max_text_size
  end

  def test_it_claims_html_and_notranslate
    capabilities = TranslationDiff::Providers::Azure.capabilities

    assert_predicate capabilities, :html?
    assert_predicate capabilities, :notranslate?
    assert_predicate capabilities, :detects_language?
    assert_predicate capabilities, :reports_billing?
  end

  private

  def echo_translations(env)
    JSON.parse(env.body).map do |item|
      { "detectedLanguage" => { "language" => "en", "score" => 1.0 },
        "translations" => [{ "text" => item["Text"], "to" => "ru" }] }
    end
  end
end
