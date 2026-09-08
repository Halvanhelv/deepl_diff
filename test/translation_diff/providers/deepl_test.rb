# frozen_string_literal: true

require "test_helper"
require "support/provider_contract"

# `TranslationDiff::Providers::DeepL.build` only requires "deepl" lazily, at
# call time, so whether ::DeepL is already defined when this file runs
# depends on test order -- Minitest randomises it. Requiring it explicitly
# here means this file's constant references (::DeepL::Exceptions::Error
# below) don't depend on some other test file having required "deepl" first.
require "deepl"

class DeepLProviderTest < Minitest::Test
  include ProviderContract

  # The provider now issues DeepL::Requests::Translate itself, one layer
  # below where the old adapter's fake client stood. Stubbing
  # DeepL::Requests::Translate is not possible without a mocking library
  # (Minitest 6.0 dropped minitest/mock), so this subclasses the provider
  # instead and overrides its private #request method -- the smallest
  # honest seam available without one, and it still exercises every line
  # of #translate and #detect.
  class FakeDeepL < TranslationDiff::Providers::DeepL
    Text = Struct.new(:text, :detected_source_language)

    attr_reader :calls

    def initialize(*)
      super(:unused_api)
      @calls = []
    end

    private

    def request(text, from, to, options = {})
      @calls << [text, from, to, options]
      Array(text).map { |value| Text.new("#{value}-translated", "EN") }
                 .then { |texts| text.is_a?(Array) ? texts : texts.first }
    end
  end

  def provider
    FakeDeepL.new
  end

  def test_translate_unwraps_the_text_of_each_result
    assert_equal %w[one-translated two-translated], provider.translate(%w[one two], from: :en, to: :ru)
  end

  def test_translate_passes_provider_options_through
    fake = FakeDeepL.new

    fake.translate(%w[one], from: :en, to: :ru, formality: :less)

    assert_equal({ formality: :less }, fake.calls.first.last.slice(:formality))
  end

  # What reaches a provider is not plain text: Tokenizer hands a notranslate
  # span over with its tags. DeepL honours `class="notranslate"` only under
  # `tag_handling: html`; without it, per DeepL's own documentation, "tags
  # are treated as regular text" -- and the protected content is translated
  # while the tags survive, which is exactly the shape of bug nobody spots.
  def test_translate_asks_for_html_tag_handling
    fake = FakeDeepL.new

    fake.translate(%w[one], from: :en, to: :ru)

    assert_equal({ tag_handling: :html, tag_handling_version: "v2" },
                 fake.calls.first.last.slice(:tag_handling, :tag_handling_version))
  end

  def test_translate_lets_the_caller_override_the_tag_handling
    fake = FakeDeepL.new

    fake.translate(%w[one], from: :en, to: :ru, tag_handling: :xml)

    assert_equal :xml, fake.calls.first.last[:tag_handling]
  end

  def test_detect_downcases_the_language
    assert_equal "en", provider.detect("etwas")
  end

  # DeepL has no detection endpoint, so the provider supplies a target of
  # its own rather than making the caller invent one.
  def test_detect_supplies_its_own_target_language
    fake = FakeDeepL.new

    fake.detect("etwas")

    assert_equal [["etwas", nil, "EN", {}]], fake.calls
  end

  def test_build_sends_a_free_key_to_the_free_host
    config = TranslationDiff::Configuration.new
    config.deepl_api_key = "abc:fx"

    provider = TranslationDiff::Providers::DeepL.build(config)
    host = provider.instance_variable_get(:@api).configuration.host

    assert_equal "https://api-free.deepl.com", host
  end

  # Regression test for a content and credential leak. deepl-rb logs the
  # whole request at DEBUG -- the Authorization header, DeepL auth key and
  # all, plus the text being translated -- so forwarding this library's
  # `config.logger` into DeepL::Configuration wrote customers' content and
  # the API key into the application log the moment anyone turned DEBUG on.
  # This gem guarantees its own log lines carry none of that, so the logger
  # must not cross into deepl-rb.
  def test_build_does_not_forward_the_logger_into_deepl_rb
    config = TranslationDiff::Configuration.new
    config.deepl_api_key = "abc:fx"
    config.logger = Object.new

    provider = TranslationDiff::Providers::DeepL.build(config)

    assert_nil provider.instance_variable_get(:@api).configuration.logger
  end

  def test_build_raises_when_no_key_is_available
    original = ENV.fetch("DEEPL_AUTH_KEY", nil)
    ENV["DEEPL_AUTH_KEY"] = nil
    config = TranslationDiff::Configuration.new

    assert_raises(::DeepL::Exceptions::Error) { TranslationDiff::Providers::DeepL.build(config) }
  ensure
    ENV["DEEPL_AUTH_KEY"] = original
  end
end
