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

  # Always lets the call through, so the `rate_limit` event fires without a real Redis connection.
  class FakeRateLimiter
    def check(_size) = nil
  end

  def setup
    super
    @recorder = Recorder.new
    TranslationDiff.configure do |c|
      c.provider = :null
      # Pinned so a developer with REDIS_URL set doesn't have these tests open a real socket.
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

  # `characters` here is what this call considered, whatever the cache had -- `request`'s `characters` is only
  # what one batch actually sent, so a fully-cached call reports here and never has a `request` event at all.
  def test_the_translate_event_carries_the_characters_this_call_considered
    TranslationDiff.translate("Hello there.", from: "en", to: "ru")

    payload = @recorder.events.find { |name, _| name == "translate.translation_diff" }.last

    assert_equal "Hello there.".size, payload[:characters]
  end

  def test_every_event_from_one_call_carries_the_same_call_id
    TranslationDiff.translate("Hello there.", from: "en", to: "ru")

    call_ids = @recorder.events.map { |_, payload| payload[:call_id] }

    refute_nil call_ids.first
    assert_equal [call_ids.first] * call_ids.size, call_ids
  end

  # A thread-safe stand-in for Recorder, so two concurrent calls can share one instrumenter without racing.
  class ThreadSafeRecorder
    def initialize
      @events = []
      @mutex = Mutex.new
    end

    def events = @mutex.synchronize { @events.dup }

    def instrument(name, payload)
      @mutex.synchronize { @events << [name, payload] }
      yield if block_given?
    end
  end

  def test_two_concurrent_calls_never_share_a_call_id
    recorder = ThreadSafeRecorder.new
    TranslationDiff.configure { |c| c.instrumenter = recorder }
    run_concurrently(2) { TranslationDiff.translate("Hello there.", from: "en", to: "ru") }

    call_ids = translate_call_ids(recorder)

    assert_equal 2, call_ids.size
    assert_equal 2, call_ids.uniq.size
  end

  def run_concurrently(count, &)
    Array.new(count) { Thread.new(&) }.each(&:join)
  end

  def translate_call_ids(recorder)
    recorder.events.filter_map { |event| event.last[:call_id] if event.first == "translate.translation_diff" }
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

  # Reports billing, so `reported` is true and the count is the provider's own claim.
  class Billing < TranslationDiff::Provider
    def self.capabilities
      TranslationDiff::Capabilities.new(
        max_request_size: 1_000_000, max_batch_size: 1_000_000, max_text_size: nil,
        html: :none, notranslate: false, detects_language: false, reports_billing: true
      )
    end

    def translate(request)
      TranslationDiff::Translation::Response.build(
        request: request, texts: request.texts.map(&:to_s),
        usage: TranslationDiff::Translation::Usage.new(
          characters: request.texts.sum(&:size), billed_characters: 42, model: "billing-v1"
        )
      )
    end

    def cache_key = "billing"
  end

  def test_the_usage_event_carries_what_the_provider_reported
    TranslationDiff.translate("Hello there.", from: "en", to: "ru", provider: Billing.new(TranslationDiff.config))

    payload = usage_event_payload

    assert_equal "billing", payload[:provider]
    assert_equal "Hello there.".size, payload[:characters]
    assert_equal 42, payload[:billed_characters]
    assert payload[:reported]
    assert_equal "billing-v1", payload[:model]
  end

  # nil billed_characters alone cannot distinguish "never says" from "did not say this time".
  def test_a_provider_that_does_not_report_billing_says_so
    TranslationDiff.translate("Hello there.", from: "en", to: "ru")

    payload = usage_event_payload

    assert_equal "null", payload[:provider]
    assert_nil payload[:billed_characters]
    refute payload[:reported]
    assert_equal "Hello there.".size, payload[:characters]
  end

  ALL_EVENT_NAMES = %w[translate.translation_diff cache.translation_diff
                       request.translation_diff rate_limit.translation_diff
                       usage.translation_diff].sort.freeze

  # A guard that only checked payload content would pass even if an event quietly stopped firing.
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

  private

  def usage_event_payload
    @recorder.events.find { |name, _| name == "usage.translation_diff" }.last
  end
end
