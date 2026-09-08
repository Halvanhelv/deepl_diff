# frozen_string_literal: true

require "test_helper"

class InstrumentationTest < ConfiguredTest
  class Recorder
    attr_reader :events

    def initialize = @events = []

    def instrument(name, payload)
      @events << [name, payload]
      yield if block_given?
    end
  end

  def setup
    super
    @recorder = Recorder.new
    TranslationDiff.configure do |c|
      c.provider = :null
      c.instrumenter = @recorder
    end
  end

  def test_a_translation_emits_translate_cache_and_request_events
    TranslationDiff.translate("Hello there.", from: "en", to: "ru")

    names = @recorder.events.map(&:first)

    assert_includes names, "translate.translation_diff"
    assert_includes names, "cache.translation_diff"
    assert_includes names, "request.translation_diff"
  end

  def test_the_translate_event_carries_languages_provider_and_a_count
    TranslationDiff.translate(%w[one two], from: "en", to: "ru")

    payload = @recorder.events.find { |name, _| name == "translate.translation_diff" }.last

    assert_equal "en", payload[:from]
    assert_equal "ru", payload[:to]
    assert_equal "null", payload[:provider]
    assert_equal 2, payload[:values]
  end

  def test_the_cache_event_carries_hit_and_miss_counts
    TranslationDiff.translate("Hello there.", from: "en", to: "ru")

    payload = @recorder.events.find { |name, _| name == "cache.translation_diff" }.last

    assert_equal 0, payload[:hits]
    assert_equal 1, payload[:misses]
  end

  def test_no_payload_ever_contains_the_text_being_translated
    secret = "Zaphod Beeblebrox is president."
    TranslationDiff.translate(secret, from: "en", to: "ru")

    serialised = @recorder.events.map { |name, payload| "#{name}#{payload}" }.join

    refute_includes serialised, "Zaphod"
    refute_includes serialised, secret
  end

  def test_translating_without_an_instrumenter_still_works
    TranslationDiff.configure { |c| c.instrumenter = nil }

    assert_equal "Hello.", TranslationDiff.translate("Hello.", from: "en", to: "ru")
  end
end
