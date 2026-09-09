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

  # Assignable via `config.rate_limiter =`, same as `config.cache =`. Always
  # lets the call through, so `check_rate_limit` has something to call
  # without needing a real Redis connection -- and so the `rate_limit` event
  # fires on every translation in this file, alongside `translate`, `cache`
  # and `request`.
  class FakeRateLimiter
    def check(_size) = nil
  end

  # TranslationDiff::Providers::Null now speaks Translation::Request/Response
  # (provider-transport work); request.rb still calls a provider the old way
  # and is migrated onto the new contract in a later task. This double keeps
  # that old shape -- and the "null" cache key the assertions below check --
  # so this file can keep exercising the instrumentation pipeline without
  # touching request.rb.
  class NullDouble
    # rubocop:disable-next Lint/UnusedMethodArgument
    def translate(texts, from:, to:, **_options) = texts
    def max_request_size = 1_000_000
    def max_batch_size = 1_000_000
    def cache_key = "null"
  end

  def setup
    super
    @recorder = Recorder.new
    TranslationDiff.configure do |c|
      c.provider = NullDouble.new
      # Pinned so a developer with REDIS_URL set does not have these tests
      # resolve the Redis store and open a real socket -- the same reason
      # context_test.rb pins it. It weakens no assertion here.
      c.cache = :memory
      c.instrumenter = @recorder
      c.rate_limiter = FakeRateLimiter.new
    end
  end

  def test_a_translation_emits_translate_cache_request_and_rate_limit_events
    TranslationDiff.translate("Hello there.", from: "en", to: "ru")

    names = @recorder.events.map(&:first)

    assert_includes names, "translate.translation_diff"
    assert_includes names, "cache.translation_diff"
    assert_includes names, "request.translation_diff"
    assert_includes names, "rate_limit.translation_diff"
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

  def test_the_rate_limit_event_carries_the_provider_and_a_character_count
    TranslationDiff.translate("Hello there.", from: "en", to: "ru")

    payload = @recorder.events.find { |name, _| name == "rate_limit.translation_diff" }.last

    assert_equal "null", payload[:provider]
    assert_equal "Hello there.".size, payload[:characters]
  end

  ALL_EVENT_NAMES = %w[translate.translation_diff cache.translation_diff
                       request.translation_diff rate_limit.translation_diff].sort.freeze

  # A guard that only checked payload content would pass even if an event
  # quietly stopped firing -- asserting the full set of names first makes
  # sure every event this library emits is actually present and inspected,
  # not just whichever ones happened to show up.
  def test_no_payload_ever_contains_the_text_being_translated
    secret = "Zaphod Beeblebrox is president."
    TranslationDiff.translate(secret, from: "en", to: "ru")

    assert_equal ALL_EVENT_NAMES, @recorder.events.map(&:first).sort

    serialised = @recorder.events.map { |name, payload| "#{name}#{payload}" }.join
    refute_includes serialised, "Zaphod"
    refute_includes serialised, secret
  end

  def test_translating_without_an_instrumenter_still_works
    TranslationDiff.configure { |c| c.instrumenter = nil }

    assert_equal "Hello.", TranslationDiff.translate("Hello.", from: "en", to: "ru")
  end
end
