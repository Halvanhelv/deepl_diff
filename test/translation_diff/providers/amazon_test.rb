require "test_helper"
require "support/provider_contract"
require "support/http_provider_contract"
require "support/env_stub"
require "faraday"
require "aws-sigv4"

class AmazonProviderTest < Minitest::Test
  include ProviderContract
  include HTTPProviderContract
  include EnvStub

  attr_reader :config, :requests

  def setup
    TranslationDiff.reset!
    @config = TranslationDiff::Configuration.new
    @config.amazon_access_key_id = "AKIAEXAMPLE"
    @config.amazon_secret_access_key = "secret"
    @config.amazon_region = "eu-central-1"
    @requests = []
  end

  # No AWS key was available: shaped from Amazon's "TranslateText" reference (read 2026-09-09), not observed.
  def provider(texts: nil)
    built = TranslationDiff::Providers::Amazon.new(config)
    built.name = :amazon
    built.instance_variable_set(:@connection, built.send(:build_connection) do |faraday|
      faraday.adapter :test, build_stubs(texts)
    end)
    built
  end

  def build_stubs(texts)
    recorder = @requests
    Faraday::Adapter::Test::Stubs.new do |stub|
      stub.post("/") { |env| respond_to_translate(env, texts, recorder) }
    end
  end

  def respond_to_translate(env, texts, recorder)
    # Faraday's test adapter mutates this env's body in place for the response -- dup it now, or lose the request.
    recorder << env.dup
    body = JSON.parse(env.body)
    translated = texts&.shift || "#{body['Text']}-ru"
    [200, { "Content-Type" => "application/x-amz-json-1.1" },
     { "TranslatedText" => translated, "SourceLanguageCode" => "en",
       "TargetLanguageCode" => "ru" }.to_json]
  end

  # Deliberate: aws-sigv4 takes explicit credentials and this library does not implement the credential chain.
  def test_it_reads_no_aws_environment_variables
    with_env("AWS_ACCESS_KEY_ID" => "AKIAENV", "AWS_SECRET_ACCESS_KEY" => "secret",
             "AWS_REGION" => "eu-west-1") do
      fresh = TranslationDiff::Configuration.new

      assert_nil fresh.amazon_access_key_id
      assert_nil fresh.amazon_secret_access_key
      assert_nil fresh.amazon_region
    end
  end

  # Amazon Translate rejected "EN"/"RU" outright, on every call.
  def test_it_downcases_a_bare_language_code_whichever_casing_the_caller_used
    provider.translate(translation_request(%w[one], from: "EN", to: "RU"))
    body = JSON.parse(requests.first.body)

    assert_equal "en", body["SourceLanguageCode"]
    assert_equal "ru", body["TargetLanguageCode"]
  end

  def test_it_leaves_a_subtagged_code_untouched
    provider.translate(translation_request(%w[one], from: "zh-Hans", to: "pt-BR"))
    body = JSON.parse(requests.first.body)

    assert_equal "zh-Hans", body["SourceLanguageCode"]
    assert_equal "pt-BR", body["TargetLanguageCode"]
  end

  def test_the_endpoint_is_regional
    assert_equal "https://translate.eu-central-1.amazonaws.com",
                 TranslationDiff::Providers::Amazon.new(config).api_base
  end

  def test_missing_credentials_are_named_before_any_request
    config.amazon_secret_access_key = nil

    error = assert_raises(TranslationDiff::ConfigurationError) do
      TranslationDiff::Providers::Amazon.new(config)
    end

    assert_match(/amazon_secret_access_key/, error.message)
  end

  def test_it_sends_the_json_rpc_target_header
    provider.translate(translation_request(%w[one]))

    assert_equal "AWSShineFrontendService_20170701.TranslateText",
                 requests.first.request_headers["X-Amz-Target"]
  end

  # Runs against the real aws-sigv4 library, not a stand-in, so this is real evidence signing works.
  def test_it_signs_the_request
    provider.translate(translation_request(%w[one]))
    authorization = requests.first.request_headers["Authorization"]

    assert_match(/\AAWS4-HMAC-SHA256 Credential=AKIAEXAMPLE/, authorization)
    assert_match(/Signature=[0-9a-f]{64}\z/, authorization)
  end

  def test_it_sends_one_text_per_call_because_the_api_has_no_batch
    provider(texts: %w[один два три]).translate(translation_request(%w[one two three]))

    assert_equal 3, requests.size
    sent = requests.map { |r| JSON.parse(r.body)["Text"] }

    assert_equal %w[one two three], sent
  end

  def test_it_returns_the_translations_in_the_order_they_were_asked_for
    response = provider(texts: %w[один два три]).translate(translation_request(%w[one two three]))

    assert_equal %w[один два три], response.texts
  end

  def test_a_missing_source_language_becomes_auto
    provider.translate(translation_request(%w[one], from: nil))

    assert_equal "auto", JSON.parse(requests.first.body)["SourceLanguageCode"]
  end

  def test_it_reports_the_source_language_amazon_resolved
    response = provider.translate(translation_request(%w[one], from: nil))

    assert_equal "en", response.detected_source
  end

  # The capability is the warning: Amazon has no HTML mode, so a notranslate span sent to it WILL be translated.
  def test_it_claims_neither_html_nor_notranslate
    capabilities = TranslationDiff::Providers::Amazon.capabilities

    refute_predicate capabilities, :html?
    refute_predicate capabilities, :notranslate?
    assert_equal 1, capabilities.max_batch_size
    assert_equal 10_000, capabilities.max_text_size
  end
end
