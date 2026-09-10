require "test_helper"
require "faraday"
require "aws-sigv4"

class ProviderLanguagesTest < Minitest::Test
  JSON_HEADERS = { "Content-Type" => "application/json" }.freeze

  def setup = TranslationDiff.reset!

  def test_deepl_asks_for_both_directions
    provider = build(TranslationDiff::Providers::DeepL, deepl_api_key: "test-key:fx") do |stub|
      stub.get("/v2/languages?type=source") { [200, JSON_HEADERS, JSON.generate([{ "language" => "EN" }])] }
      stub.get("/v2/languages?type=target") { [200, JSON_HEADERS, JSON.generate([{ "language" => "EN-GB" }])] }
    end

    assert_equal({ source: %w[EN], target: %w[EN-GB] }, provider.languages)
  end

  # The source-list URL is enough to document what #languages fetches; DeepL also asks a target one.
  def test_deepls_languages_endpoint_is_the_source_list_url
    provider = build(TranslationDiff::Providers::DeepL, deepl_api_key: "test-key")

    assert_equal "https://api.deepl.com/v2/languages", provider.languages_endpoint
  end

  def test_google_asks_once_and_uses_the_same_list_both_ways
    provider = build(TranslationDiff::Providers::Google, google_api_key: "test-key") do |stub|
      stub.get("/language/translate/v2/languages?key=test-key") do
        [200, JSON_HEADERS,
         JSON.generate({ "data" => { "languages" => [{ "language" => "en" }, { "language" => "ru" }] } })]
      end
    end

    assert_equal({ source: %w[en ru], target: %w[en ru] }, provider.languages)
  end

  def test_googles_languages_endpoint_omits_the_credential
    provider = build(TranslationDiff::Providers::Google, google_api_key: "test-key")

    assert_equal "https://translation.googleapis.com/language/translate/v2/languages", provider.languages_endpoint
  end

  def test_azure_reads_the_translation_hashs_keys
    provider = build(TranslationDiff::Providers::Azure, azure_api_key: "test-key") do |stub|
      stub.get("/languages?api-version=3.0&scope=translation") do
        [200, JSON_HEADERS, JSON.generate({ "translation" => { "en" => {}, "ru" => {} } })]
      end
    end

    assert_equal({ source: %w[en ru], target: %w[en ru] }, provider.languages)
  end

  def test_azures_languages_endpoint_is_the_full_url_it_fetches
    provider = build(TranslationDiff::Providers::Azure, azure_api_key: "test-key")

    assert_equal "https://api.cognitive.microsofttranslator.com/languages?api-version=3.0&scope=translation",
                 provider.languages_endpoint
  end

  def test_modernmt_reads_the_data_array
    provider = build(TranslationDiff::Providers::ModernMT, modernmt_api_key: "test-key") do |stub|
      stub.get("/translate/languages") { [200, JSON_HEADERS, JSON.generate({ "data" => %w[en ru] })] }
    end

    assert_equal({ source: %w[en ru], target: %w[en ru] }, provider.languages)
  end

  def test_modernmts_languages_endpoint_is_the_full_url_it_fetches
    provider = build(TranslationDiff::Providers::ModernMT, modernmt_api_key: "test-key")

    assert_equal "https://api.modernmt.com/translate/languages", provider.languages_endpoint
  end

  def test_libretranslate_reads_each_entrys_own_targets
    provider = build(TranslationDiff::Providers::LibreTranslate,
                     libretranslate_api_base: "https://libretranslate.test") do |stub|
      stub.get("/languages") do
        [200, JSON_HEADERS,
         JSON.generate([{ "code" => "en", "targets" => %w[ru fr] }, { "code" => "fr", "targets" => %w[en] }])]
      end
    end

    assert_equal({ source: %w[en fr], target: %w[ru fr en] }, provider.languages)
  end

  def test_libretranslates_languages_endpoint_is_the_full_url_it_fetches
    provider = build(TranslationDiff::Providers::LibreTranslate,
                     libretranslate_api_base: "https://libretranslate.test")

    assert_equal "https://libretranslate.test/languages", provider.languages_endpoint
  end

  def test_amazon_sends_the_list_languages_target_and_reads_language_codes
    requests = []
    provider = build(TranslationDiff::Providers::Amazon,
                     amazon_access_key_id: "AKIAEXAMPLE", amazon_secret_access_key: "secret",
                     amazon_region: "eu-central-1") { |stub| stub.post("/", &record(requests)) }

    assert_equal({ source: %w[en ru], target: %w[en ru] }, provider.languages)
    assert_equal "AWSShineFrontendService_20170701.ListLanguages", requests.first.request_headers["X-Amz-Target"]
  end

  # Amazon has no distinct languages URL: every call, including ListLanguages, is a signed POST to the root.
  def test_amazons_languages_endpoint_is_its_signed_root
    provider = build(TranslationDiff::Providers::Amazon,
                     amazon_access_key_id: "AKIAEXAMPLE", amazon_secret_access_key: "secret",
                     amazon_region: "eu-central-1")

    assert_equal "https://translate.eu-central-1.amazonaws.com/", provider.languages_endpoint
  end

  private

  # Records the raw request so the header assertion can inspect what was actually signed and sent.
  def record(requests)
    lambda do |env|
      requests << env.dup
      [200, JSON_HEADERS, JSON.generate({ "Languages" => [{ "LanguageCode" => "en" }, { "LanguageCode" => "ru" }] })]
    end
  end

  def build(provider_class, **config_values, &)
    config = TranslationDiff::Configuration.new
    config_values.each { |key, value| config.public_send(:"#{key}=", value) }
    stubs = Faraday::Adapter::Test::Stubs.new(&)

    provider_class.new(config).tap do |built|
      built.name = :"languages-test"
      built.instance_variable_set(:@connection,
                                  built.send(:build_connection) { |faraday| faraday.adapter :test, stubs })
    end
  end
end
