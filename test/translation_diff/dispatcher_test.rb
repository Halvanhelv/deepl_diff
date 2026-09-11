require "test_helper"

class DispatcherTest < ConfiguredTest
  class RecordingProvider < TranslationDiff::Provider
    def self.capabilities
      TranslationDiff::Capabilities.new(
        max_request_size: 1_000, max_batch_size: 10, max_text_size: nil,
        html: :none, notranslate: false, detects_language: false, reports_billing: false
      )
    end

    attr_reader :requests

    def initialize(config)
      super
      @requests = []
    end

    def translate(request)
      @requests << request
      TranslationDiff::Translation::Response.build(request: request, texts: request.texts.map(&:upcase))
    end

    def cache_key = "recording"
  end

  # Its Usage claims a wrong character count -- the library's own tally must win in the event anyway.
  class MisreportingProvider < RecordingProvider
    def self.capabilities
      TranslationDiff::Capabilities.new(
        max_request_size: 1_000, max_batch_size: 10, max_text_size: nil,
        html: :none, notranslate: false, detects_language: false, reports_billing: true
      )
    end

    def translate(request)
      @requests << request
      usage = TranslationDiff::Translation::Usage.new(characters: 999_999, billed_characters: 3, model: "x-model")
      TranslationDiff::Translation::Response.build(request: request, texts: request.texts.map(&:upcase), usage: usage)
    end

    def cache_key = "misreporting"
  end

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
    attr_reader :sizes

    def initialize = @sizes = []

    def check(size) = @sizes << size
  end

  def segments(*sources) = sources.map { |s| TranslationDiff::Segment.new(s) }

  def dispatcher(provider, call_id: "call-1", **)
    TranslationDiff::Dispatcher.new(provider: provider, from: "en", to: "ru", call_id: call_id, **)
  end

  def configured(**settings)
    config = TranslationDiff::Configuration.new
    settings.each { |key, value| config.public_send("#{key}=", value) }
    config
  end

  # Dispatches the given texts through the given provider, and hands back everything it instrumented.
  def instrumented(provider, *sources, call_id: "call-1", **settings)
    recorder = Recorder.new
    config = configured(instrumenter: recorder, **settings)
    dispatcher(provider, config: config, call_id: call_id).dispatch(segments(*sources))
    recorder
  end

  def payload_for(recorder, event)
    recorder.events.find { |name, _| name == "#{event}.translation_diff" }.last
  end

  def test_dispatch_applies_the_reply_to_the_segments_that_produced_it
    provider = RecordingProvider.new(TranslationDiff::Configuration.new)
    segs = segments("one", "two")

    dispatcher(provider).dispatch(segs)

    assert_equal %w[ONE TWO], segs.map(&:translation)
  end

  def test_the_request_carries_the_from_and_to_languages
    provider = RecordingProvider.new(TranslationDiff::Configuration.new)

    dispatcher(provider).dispatch(segments("one"))

    request = provider.requests.first
    assert_equal "en", request.from
    assert_equal "ru", request.to
  end

  def test_the_request_event_carries_the_provider_a_batch_size_and_a_character_count
    recorder = instrumented(RecordingProvider.new(TranslationDiff::Configuration.new), "Hello there.")
    payload = payload_for(recorder, "request")

    assert_equal "recording", payload[:provider]
    assert_equal 1, payload[:batch]
    assert_equal "Hello there.".size, payload[:characters]
  end

  # The design says `characters` is what this library sent, always known, so a provider's own count never wins.
  def test_the_usage_event_reports_the_locally_counted_characters_even_when_the_provider_misreports_them
    recorder = instrumented(MisreportingProvider.new(TranslationDiff::Configuration.new), "one two")
    payload = payload_for(recorder, "usage")

    assert_equal "one two".size, payload[:characters]
    refute_equal 999_999, payload[:characters]
  end

  def test_the_usage_event_still_reads_billed_characters_and_model_from_the_provider
    recorder = instrumented(MisreportingProvider.new(TranslationDiff::Configuration.new), "one")
    payload = payload_for(recorder, "usage")

    assert_equal 3, payload[:billed_characters]
    assert_equal "x-model", payload[:model]
    assert_equal true, payload[:reported]
  end

  def test_no_rate_limit_event_without_a_rate_limiter
    recorder = instrumented(RecordingProvider.new(TranslationDiff::Configuration.new), "one")

    refute_includes recorder.events.map(&:first), "rate_limit.translation_diff"
  end

  def test_the_rate_limiter_is_consulted_before_the_request_with_the_characters_about_to_be_sent
    limiter = FakeRateLimiter.new
    provider = RecordingProvider.new(TranslationDiff::Configuration.new)
    recorder = instrumented(provider, "one two", rate_limiter: limiter)

    names = recorder.events.map(&:first).select { |name| name.start_with?("rate_limit", "request") }
    assert_equal %w[rate_limit.translation_diff request.translation_diff], names
    assert_equal ["one two".size], limiter.sizes
  end

  # Dispatcher emits three of the six events, so it is handed the call's identifier rather than inventing its own.
  def test_the_call_id_it_is_given_appears_in_every_event_it_emits
    limiter = FakeRateLimiter.new
    provider = RecordingProvider.new(TranslationDiff::Configuration.new)
    recorder = instrumented(provider, "one two", rate_limiter: limiter, call_id: "abc123")

    assert_equal "abc123", payload_for(recorder, "request")[:call_id]
    assert_equal "abc123", payload_for(recorder, "rate_limit")[:call_id]
    assert_equal "abc123", payload_for(recorder, "usage")[:call_id]
  end

  def test_no_payload_ever_contains_the_text_being_translated
    secret = "Zaphod Beeblebrox is president."
    provider = RecordingProvider.new(TranslationDiff::Configuration.new)
    recorder = instrumented(provider, secret, rate_limiter: FakeRateLimiter.new)

    serialised = recorder.events.map { |name, payload| "#{name}#{payload}" }.join
    refute_includes serialised, "Zaphod"
    refute_includes serialised, secret
    refute_includes serialised, secret.upcase
  end
end
