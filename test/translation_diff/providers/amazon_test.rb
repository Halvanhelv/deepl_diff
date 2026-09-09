# frozen_string_literal: true

require "test_helper"
require "support/provider_contract"
require "support/http_provider_contract"
require "faraday"
require "aws-sigv4"

class AmazonProviderTest < Minitest::Test
  include ProviderContract
  include HTTPProviderContract

  attr_reader :config, :requests

  def setup
    TranslationDiff.reset!
    @config = TranslationDiff::Configuration.new
    @config.amazon_access_key_id = "AKIAEXAMPLE"
    @config.amazon_secret_access_key = "secret"
    @config.amazon_region = "eu-central-1"
    @requests = []
  end

  # There is no AWS key available for this task, so unlike DeepL's and
  # Google's fixtures -- both captured from a live call -- this response
  # body is shaped from Amazon's own Translate API reference documentation
  # ("TranslateText", read 2026-09-09), not from an observed response.
  # Nobody should mistake it for one.
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
    # Faraday's test adapter reuses this env for the response, mutating its
    # body in place once the block returns -- capture a copy now or every
    # read after #translate returns sees the reply, not the request (see
    # test/support/stubbed_provider.rb).
    recorder << env.dup
    body = JSON.parse(env.body)
    translated = texts&.shift || "#{body['Text']}-ru"
    [200, { "Content-Type" => "application/x-amz-json-1.1" },
     { "TranslatedText" => translated, "SourceLanguageCode" => "en",
       "TargetLanguageCode" => "ru" }.to_json]
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

  # This runs against the real aws-sigv4 library rather than a stand-in, so
  # it is real evidence that this provider signs correctly -- not just that
  # some string ended up in the Authorization header.
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

  # The capability is the warning. Amazon has no HTML mode at all, so a
  # notranslate span sent to it WILL be translated, and the only honest thing
  # to do is say so where the rest of the library can read it.
  def test_it_claims_neither_html_nor_notranslate
    capabilities = TranslationDiff::Providers::Amazon.capabilities

    refute_predicate capabilities, :html?
    refute_predicate capabilities, :notranslate?
    assert_equal 1, capabilities.max_batch_size
    assert_equal 10_000, capabilities.max_text_size
  end
end
