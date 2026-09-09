require "test_helper"
require "support/provider_contract"
require "support/http_provider_contract"
require "support/stubbed_provider"
require "faraday"

class ModernMTProviderTest < Minitest::Test
  include ProviderContract
  include HTTPProviderContract
  include StubbedProvider

  # Shaped from modernmt.com/api's reference (read 2026-09-09), not a live call: no key was available.
  BODY = { "data" => [
    { "translation" => "один", "billedCharacters" => 3, "characters" => 3, "detectedLanguage" => "en" },
    { "translation" => "два", "billedCharacters" => 3, "characters" => 3, "detectedLanguage" => "en" }
  ] }.freeze

  attr_reader :config

  def setup
    TranslationDiff.reset!
    @config = TranslationDiff::Configuration.new
    @config.modernmt_api_key = "test-key"
  end

  def provider_class = TranslationDiff::Providers::ModernMT

  # Left nil, `body:` echoes back whatever texts were sent, so ProviderContract's count check never trips.
  def provider(body: nil, status: 200, headers: {})
    stub_provider(route: "/translate", body: body || method(:echo_translations),
                  status: status, headers: headers, name: :modernmt)
  end

  def test_it_sends_the_key_in_the_documented_header
    assert_equal "test-key",
                 TranslationDiff::Providers::ModernMT.new(config).headers["MMT-ApiKey"]
  end

  def test_it_sends_the_texts_and_the_language_pair_in_the_body
    provider.translate(translation_request(%w[one two]))

    assert_equal %w[one two], sent["q"]
    assert_equal "en", sent["source"]
    assert_equal "ru", sent["target"]
  end

  def test_it_downcases_a_bare_language_code_whichever_casing_the_caller_used
    provider.translate(translation_request(%w[one], from: "EN", to: "RU"))

    assert_equal "en", sent["source"]
    assert_equal "ru", sent["target"]
  end

  def test_it_leaves_a_subtagged_code_untouched
    provider.translate(translation_request(%w[one], from: "zh-Hans", to: "pt-BR"))

    assert_equal "zh-Hans", sent["source"]
    assert_equal "pt-BR", sent["target"]
  end

  def test_it_asks_for_html_by_mime_type
    provider.translate(translation_request(%w[one]))

    assert_equal "text/html", sent["format"]
  end

  def test_it_unwraps_the_data_envelope
    response = provider(body: BODY).translate(translation_request(%w[one two]))

    assert_equal %w[один два], response.texts
    assert_equal "en", response.detected_source
    assert_equal 6, response.usage.billed_characters
  end

  # Same convention as DeepL and Azure: a reported 0 is a claim, not "unknown".
  def test_a_reported_zero_is_zero_not_unknown
    body = { "data" => [{ "translation" => "один", "billedCharacters" => 0 },
                        { "translation" => "два", "billedCharacters" => 0 }] }
    response = provider(body: body).translate(translation_request(%w[one two]))

    assert_equal 0, response.usage.billed_characters
  end

  def test_billed_characters_is_nil_when_no_result_reported_it
    body = { "data" => [{ "translation" => "один" }, { "translation" => "два" }] }
    response = provider(body: body).translate(translation_request(%w[one two]))

    assert_nil response.usage.billed_characters
  end

  # One text comes back as an object, not a one-element array, which would hand the pipeline a bare Hash.
  def test_a_single_text_comes_back_unwrapped_and_is_still_a_list
    single = { "data" => { "translation" => "один", "detectedLanguage" => "en" } }
    response = provider(body: single).translate(translation_request(%w[one]))

    assert_equal %w[один], response.texts
  end

  def test_its_batch_limit_is_the_documented_maximum
    assert_equal 128, TranslationDiff::Providers::ModernMT.capabilities.max_batch_size
  end

  private

  def echo_translations(env)
    texts = JSON.parse(env.body)["q"]
    { "data" => texts.map { |text| { "translation" => text, "detectedLanguage" => "en" } } }
  end
end
