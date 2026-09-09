# frozen_string_literal: true

require "test_helper"
require "support/provider_contract"
require "support/http_provider_contract"
require "faraday"

class DeepLProviderTest < Minitest::Test
  include ProviderContract
  include HTTPProviderContract

  # A real response body, captured from api-free.deepl.com on 2026-09-09.
  TRANSLATE_BODY = {
    "translations" => [
      { "detected_source_language" => "EN", "text" => "один", "billed_characters" => 3 },
      { "detected_source_language" => "EN", "text" => "два", "billed_characters" => 3 }
    ]
  }.freeze

  attr_reader :config, :requests

  def setup
    TranslationDiff.reset!
    @config = TranslationDiff::Configuration.new
    @config.deepl_api_key = "test-key:fx"
    @requests = []
  end

  # Builds a provider whose connection answers from a stub and records what
  # was sent, so a test can assert on the payload as well as the parse.
  #
  # When neither `body:` nor `texts:` is given, the stub echoes back
  # whatever texts were actually sent (rather than a fixed pair), so the
  # shared ProviderContract tests -- which call `provider` with no
  # knowledge of how many texts they are about to send -- get a response
  # the same size as their request instead of tripping Response.build's
  # count check.
  def provider(body: nil, status: 200, texts: nil)
    stubs = stub_translate(body: body, status: status, texts: texts)
    built = TranslationDiff::Providers::DeepL.new(config)
    built.name = :deepl
    built.instance_variable_set(:@connection, built.send(:build_connection) do |faraday|
      faraday.adapter :test, stubs
    end)
    built
  end

  def sent = JSON.parse(requests.first.body)

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

  # Regression: notranslate spans reach the provider with their tags, and
  # DeepL honours class="notranslate" only under HTML tag handling. Without
  # this the protected content is translated while the tags survive, which is
  # invisible in review.
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

  def test_a_short_response_raises_rather_than_shifting_nils_into_the_results
    short = { "translations" => [{ "text" => "один" }] }

    assert_raises(TranslationDiff::ResponseError) do
      provider(body: short).translate(translation_request(%w[one two]))
    end
  end

  # DeepL has no detection endpoint, so it detects by translating a sample
  # and reading what it says the source was. #detect sends exactly one
  # text, so the stub is given exactly one text to echo back.
  def test_detect_returns_the_language_deepl_reports
    assert_equal "en", provider(texts: %w[x]).detect("something")
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

  def stub_translate(body:, status:, texts:)
    recorder = @requests
    Faraday::Adapter::Test::Stubs.new do |stub|
      stub.post("/v2/translate") do |env|
        # Faraday's test adapter reuses this env for the response, mutating
        # its body in place once the block returns -- capture a copy now or
        # every read after #translate returns sees the reply, not the
        # request.
        recorder << env.dup
        [status, { "Content-Type" => "application/json" }, translate_response(body, texts, env).to_json]
      end
    end
  end

  def translate_response(body, texts, env)
    return body if body

    response_texts = texts || JSON.parse(env.body)["text"]
    { "translations" => response_texts.map { |t| { "text" => t, "detected_source_language" => "EN" } } }
  end
end
