# frozen_string_literal: true

require "test_helper"
require "support/provider_contract"
require "support/http_provider_contract"
require "support/stubbed_provider"
require "faraday"
require "cgi"

class GoogleProviderTest < Minitest::Test
  include ProviderContract
  include HTTPProviderContract
  include StubbedProvider

  # A real response envelope, shaped from the Cloud Translation v2 REST
  # reference read 2026-09-09: translations live under a nested "data" key,
  # not at the top level the way DeepL's do.
  TRANSLATE_BODY = {
    "data" => { "translations" => [
      { "translatedText" => "один", "detectedSourceLanguage" => "en" },
      { "translatedText" => "два", "detectedSourceLanguage" => "en" }
    ] }
  }.freeze

  attr_reader :config

  def setup
    TranslationDiff.reset!
    @config = TranslationDiff::Configuration.new
    @config.google_api_key = "test-key"
  end

  def provider_class = TranslationDiff::Providers::Google

  # When `body:` is left nil, the stub echoes back whatever texts were
  # actually sent (rather than a fixed pair), so the shared ProviderContract
  # tests -- which call `provider` with no knowledge of how many texts they
  # are about to send -- get a response the same size as their request
  # instead of tripping Response.build's count check. The content type
  # matches what Cloud Translation v2 actually sends.
  def provider(body: nil, status: 200, headers: { "Content-Type" => "application/json; charset=UTF-8" })
    stub_provider(route: "/language/translate/v2", body: body || method(:echo_translations),
                  status: status, headers: headers, name: :google)
  end

  def test_the_key_travels_in_the_query_string
    provider.translate(translation_request(%w[one]))

    assert_equal ["test-key"], query["key"]
  end

  def test_it_sends_the_texts_and_the_language_pair
    provider.translate(translation_request(%w[one two]))

    assert_equal %w[one two], sent["q"]
    assert_equal "en", sent["source"]
    assert_equal "ru", sent["target"]
  end

  def test_it_asks_for_html
    provider.translate(translation_request(%w[one]))

    assert_equal "html", sent["format"]
  end

  def test_a_caller_may_ask_for_plain_text
    provider.translate(translation_request(%w[one], format: :text))

    assert_equal "text", sent["format"]
  end

  # Google's codes are lower case and a config written for DeepL says "EN";
  # but "zh-Hans" and "pt-BR" carry subtags whose casing is their own.
  def test_it_downcases_bare_codes_and_leaves_subtagged_ones_alone
    provider.translate(translation_request(%w[one], from: "EN", to: "zh-Hans"))

    assert_equal "en", sent["source"]
    assert_equal "zh-Hans", sent["target"]
  end

  def test_it_omits_the_source_language_when_none_was_given
    provider.translate(translation_request(%w[one], from: nil))

    refute sent.key?("source")
  end

  def test_it_parses_the_nested_data_envelope
    body = { "data" => { "translations" => [
      { "translatedText" => "один", "detectedSourceLanguage" => "en" }
    ] } }
    response = provider(body: body).translate(translation_request(%w[one], from: nil))

    assert_equal %w[один], response.texts
    assert_equal "en", response.detected_source
  end

  def test_it_returns_the_translations_in_order
    response = provider(body: TRANSLATE_BODY).translate(translation_request(%w[one two]))

    assert_equal %w[один два], response.texts
  end

  def test_a_short_response_raises_rather_than_shifting_nils_into_the_results
    short = { "data" => { "translations" => [{ "translatedText" => "один" }] } }

    assert_raises(TranslationDiff::ResponseError) do
      provider(body: short).translate(translation_request(%w[one two]))
    end
  end

  def test_the_api_base_option_overrides_the_default
    config.google_api_base = "https://google.internal"

    assert_equal "https://google.internal", TranslationDiff::Providers::Google.new(config).api_base
  end

  def test_a_missing_key_is_named_before_any_request
    config.google_api_key = nil

    error = assert_raises(TranslationDiff::ConfigurationError) do
      TranslationDiff::Providers::Google.new(config)
    end

    assert_match(/google_api_key/, error.message)
  end

  def test_its_batch_limit_is_googles_documented_one_hundred_twenty_eight
    assert_equal 128, TranslationDiff::Providers::Google.capabilities.max_batch_size
  end

  def test_it_claims_html_and_notranslate
    capabilities = TranslationDiff::Providers::Google.capabilities

    assert_predicate capabilities, :html?
    assert_predicate capabilities, :notranslate?
    assert_predicate capabilities, :detects_language?
  end

  def test_google_reports_no_billing
    refute_predicate TranslationDiff::Providers::Google.capabilities, :reports_billing?
  end

  private

  def echo_translations(env)
    texts = JSON.parse(env.body)["q"]
    translations = texts.map { |t| { "translatedText" => t, "detectedSourceLanguage" => "en" } }
    { "data" => { "translations" => translations } }
  end
end
