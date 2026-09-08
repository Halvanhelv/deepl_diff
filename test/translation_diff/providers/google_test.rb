# frozen_string_literal: true

require "test_helper"
require "support/provider_contract"

# `TranslationDiff::Providers::Google.build` only requires the gem lazily, at
# call time, so whether ::Google::Cloud::Translate::V2 is already defined when
# this file runs depends on test order -- Minitest randomises it. Requiring it
# explicitly here means this file's constant references don't depend on some
# other test file having required it first.
require "google/cloud/translate/v2"

class GoogleProviderTest < Minitest::Test
  include ProviderContract

  # Stands in for Google::Cloud::Translate::V2::Api. The single/array return
  # asymmetry is copied deliberately from the real thing: Translation
  # .from_gapi_list and Detection.from_gapi both return a bare object rather
  # than a one-element array when they were given one text, and a provider
  # that forgets that hands Request a Translation where it expects an Array.
  class FakeApi
    Translation = Struct.new(:text)
    Detection = Struct.new(:language)

    attr_reader :calls

    def initialize
      @calls = []
    end

    def translate(*text, **options)
      @calls << [text, options]
      unwrap(text.map { |value| Translation.new("#{value}-translated") })
    end

    def detect(*text)
      @calls << [text, {}]
      unwrap(text.map { Detection.new("en") })
    end

    private

    def unwrap(results) = results.size == 1 ? results.first : results
  end

  def provider = TranslationDiff::Providers::Google.new(FakeApi.new)

  def test_translate_unwraps_the_text_of_each_result
    assert_equal %w[one-translated two-translated],
                 provider.translate(%w[one two], from: :en, to: :ru)
  end

  # The API hands back a bare Translation, not a one-element array, when it
  # was given one text. Request counts the results against the values it
  # sent, so a provider that passes that through fails the count check.
  def test_translate_returns_an_array_for_a_single_text
    assert_equal %w[one-translated], provider.translate(%w[one], from: :en, to: :ru)
  end

  # Google's own default is `html`, which HTML-escapes the response: an
  # apostrophe comes back as "&#39;". By the time a value reaches a provider
  # the Tokenizer has already stripped the markup, so what is being sent is
  # plain text and must be asked for as plain text.
  def test_translate_asks_for_plain_text
    api = FakeApi.new

    TranslationDiff::Providers::Google.new(api).translate(%w[one], from: :en, to: :ru)

    assert_equal :text, api.calls.first.last[:format]
  end

  def test_translate_lets_the_caller_override_the_format
    api = FakeApi.new

    TranslationDiff::Providers::Google.new(api).translate(%w[one"], from: :en, to: :ru, format: :html)

    assert_equal :html, api.calls.first.last[:format]
  end

  # A configuration written against DeepL says "EN"; Google's codes are
  # lowercase.
  def test_translate_downcases_bare_language_codes
    api = FakeApi.new

    TranslationDiff::Providers::Google.new(api).translate(%w[one], from: "EN", to: "RU")

    assert_equal({ from: "en", to: "ru" }, api.calls.first.last.slice(:from, :to))
  end

  # "zh-Hans", "zh-CN" and "pt-BR" carry subtags whose casing is their own;
  # a blanket downcase would corrupt them.
  def test_translate_passes_subtagged_codes_through_untouched
    api = FakeApi.new

    TranslationDiff::Providers::Google.new(api).translate(%w[one], from: "en", to: "zh-Hans")

    assert_equal "zh-Hans", api.calls.first.last[:to]
  end

  # No source language means "detect it", which the API does when `source`
  # is absent. Sending "" instead would be rejected.
  def test_translate_omits_the_source_language_when_none_is_given
    api = FakeApi.new

    TranslationDiff::Providers::Google.new(api).translate(%w[one], from: nil, to: :ru)

    assert_nil api.calls.first.last[:from]
  end

  def test_translate_passes_provider_options_through
    api = FakeApi.new

    TranslationDiff::Providers::Google.new(api).translate(%w[one], from: :en, to: :ru, model: "nmt")

    assert_equal "nmt", api.calls.first.last[:model]
  end

  def test_translate_sends_every_text_in_one_call
    api = FakeApi.new

    TranslationDiff::Providers::Google.new(api).translate(%w[one two three], from: :en, to: :ru)

    assert_equal 1, api.calls.size
    assert_equal %w[one two three], api.calls.first.first
  end

  def test_detect_returns_the_language
    assert_equal "en", provider.detect("etwas")
  end

  # Both numbers are Google's own, and both are load-bearing: Chunker uses
  # them to decide where to split, and a batch over 128 is rejected outright.
  def test_the_limits_are_the_documented_ones
    assert_equal 128, provider.max_batch_size
    assert_equal 5_000, provider.max_request_size
  end

  def test_build_passes_the_configured_key_to_the_api
    config = TranslationDiff::Configuration.new
    config.google_api_key = "abc"

    provider = TranslationDiff::Providers::Google.build(config)

    assert_equal "abc", provider.instance_variable_get(:@api).service.key
  end

  def test_build_passes_the_configured_project_id_to_the_api
    config = TranslationDiff::Configuration.new
    config.google_api_key = "abc"
    config.google_project_id = "a-project"

    provider = TranslationDiff::Providers::Google.build(config)

    assert_equal "a-project", provider.instance_variable_get(:@api).service.project_id
  end

  # Without a key the gem falls through to application default credentials,
  # which need a project id it cannot find in a test environment.
  def test_build_raises_when_no_key_is_available
    original = ENV.to_hash.slice("TRANSLATE_KEY", "GOOGLE_CLOUD_KEY", "TRANSLATE_PROJECT")
    original.each_key { |key| ENV[key] = nil }
    config = TranslationDiff::Configuration.new

    assert_raises(StandardError) { TranslationDiff::Providers::Google.build(config) }
  ensure
    original&.each { |key, value| ENV[key] = value }
  end

  def test_it_is_registered_under_its_own_name
    config = TranslationDiff::Configuration.new
    config.google_api_key = "abc"

    assert TranslationDiff::Providers.registered?(:google)
    assert_equal "google", TranslationDiff::Providers.build(:google, config).cache_key
  end
end
