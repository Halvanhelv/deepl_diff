# frozen_string_literal: true

require "test_helper"
require "support/provider_contract"
require "support/http_provider_contract"
require "support/stubbed_provider"
require "faraday"

class ModernMTProviderTest < Minitest::Test
  include ProviderContract
  include HTTPProviderContract
  include StubbedProvider

  # Shaped from modernmt.com/api's own "Translate" reference (read
  # 2026-09-09), not from a live call: no ModernMT key was available for this
  # task.
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

  # When `body:` is left nil, the stub echoes back whatever texts were
  # actually sent, so the shared ProviderContract tests -- which call
  # `provider` with no knowledge of how many texts they are about to send --
  # get a response the same size as their request instead of tripping
  # Response.build's count check.
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

  # One text comes back as an object, not a one-element array. A provider
  # that passes that through hands the pipeline a Hash where it expects a
  # list, and the count check is what catches it.
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
