require "test_helper"
require "support/provider_contract"
require "support/http_provider_contract"
require "support/stubbed_provider"
require "faraday"

class LibreTranslateProviderTest < Minitest::Test
  include ProviderContract
  include HTTPProviderContract
  include StubbedProvider

  attr_reader :config

  def setup
    TranslationDiff.reset!
    @config = TranslationDiff::Configuration.new
    @config.libretranslate_api_base = "https://libretranslate.test"
  end

  def provider_class = TranslationDiff::Providers::LibreTranslate

  # Left nil, `body:` echoes back whatever texts were sent, so ProviderContract's count check never trips.
  def provider(body: nil, status: 200, headers: {})
    stub_provider(route: "/translate", body: body || method(:echo_translations),
                  status: status, headers: headers, name: :libretranslate)
  end

  # Everyone self-hosts this one, so base URL is the requirement and key is the option -- the reverse of the rest.
  def test_the_api_base_is_required_and_the_key_is_not
    config.libretranslate_api_base = nil

    error = assert_raises(TranslationDiff::ConfigurationError) do
      TranslationDiff::Providers::LibreTranslate.new(config)
    end

    assert_match(/libretranslate_api_base/, error.message)
  end

  def test_the_key_travels_in_the_body_when_set
    config.libretranslate_api_key = "test-key"
    provider.translate(translation_request(%w[one]))

    assert_equal "test-key", sent["api_key"]
  end

  def test_the_key_is_absent_from_the_body_when_unset
    provider.translate(translation_request(%w[one]))

    refute sent.key?("api_key")
  end

  # source is required by the API, and "auto" is how detection is asked for.
  def test_a_missing_source_language_becomes_auto
    provider.translate(translation_request(%w[one], from: nil))

    assert_equal "auto", sent["source"]
  end

  def test_it_asks_for_html
    provider.translate(translation_request(%w[one]))

    assert_equal "html", sent["format"]
  end

  def test_it_reads_an_array_response
    body = { "translatedText" => %w[один два],
             "detectedLanguage" => [{ "language" => "en", "confidence" => 92.0 }] }
    response = provider(body: body).translate(translation_request(%w[one two]))

    assert_equal %w[один два], response.texts
    assert_equal "en", response.detected_source
  end

  # A single q comes back as a bare string, not a one-element array.
  def test_it_reads_a_single_string_response
    body = { "translatedText" => "один", "detectedLanguage" => { "language" => "en" } }
    response = provider(body: body).translate(translation_request(%w[one]))

    assert_equal %w[один], response.texts
  end

  def test_a_short_response_raises_rather_than_shifting_nils_into_the_results
    short = { "translatedText" => "один" }

    assert_raises(TranslationDiff::ResponseError) do
      provider(body: short).translate(translation_request(%w[one two]))
    end
  end

  def test_detect_returns_the_language_libretranslate_reports
    detector = stub_provider(route: "/detect", body: [{ "language" => "en", "confidence" => 92.0 }],
                             name: :libretranslate)

    assert_equal "en", detector.detect("something")
  end

  def test_its_batch_limit_is_this_librarys_own_conservative_choice
    assert_equal 50, TranslationDiff::Providers::LibreTranslate.capabilities.max_batch_size
  end

  private

  def echo_translations(env)
    texts = JSON.parse(env.body)["q"]
    { "translatedText" => texts, "detectedLanguage" => texts.map { { "language" => "en" } } }
  end
end
