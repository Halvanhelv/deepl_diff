require "test_helper"

class TranslatorTest < ConfiguredTest
  class RecordingProvider < TranslationDiff::Provider
    def self.capabilities
      TranslationDiff::Capabilities.new(
        max_request_size: 1_000, max_batch_size: 10, max_text_size: nil,
        html: :none, notranslate: false, detects_language: true, reports_billing: false
      )
    end

    attr_reader :requests

    def initialize(config)
      super
      @requests = []
    end

    def translate(request)
      @requests << request
      TranslationDiff::Translation::Response.build(
        request: request, texts: request.texts.map(&:upcase)
      )
    end

    def detect(_text) = "en"
    def cache_key = "recording"
  end

  # The capability is the only honest test: every provider inherits a #detect that raises.
  class BlindProvider < RecordingProvider
    def self.capabilities
      TranslationDiff::Capabilities.new(
        max_request_size: 1_000, max_batch_size: 10, max_text_size: nil,
        html: :none, notranslate: false, detects_language: false, reports_billing: false
      )
    end

    def cache_key = "blind"
  end

  # An empty cache key would file this provider's translations in every other provider's namespace.
  class NamelessProvider < RecordingProvider
    def cache_key = "   "
  end

  class FakeLogger
    attr_reader :lines

    def initialize = @lines = []

    def debug(&) = @lines << yield
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

  def setup
    super
    @provider = RecordingProvider.new(TranslationDiff::Configuration.new)
    # Pinned so a developer with REDIS_URL set doesn't have these tests open a real socket.
    TranslationDiff.configure { |c| c.cache = :memory }
  end

  def translate(values, **)
    TranslationDiff::Translator.new(values, provider: @provider, **).call
  end

  def test_it_translates_a_nested_structure_and_keeps_its_shape
    result = translate({ title: "one.", body: ["two.", 42] }, from: "en", to: "ru")

    assert_equal({ title: "ONE.", body: ["TWO.", 42] }, result)
  end

  def test_the_same_language_never_reaches_the_provider
    assert_equal "one.", translate("one.", from: "en", to: "en")
    assert_empty @provider.requests
  end

  def test_the_same_language_is_compared_across_string_and_symbol
    assert_equal "one.", translate("one.", from: "EN", to: :en)
    assert_empty @provider.requests
  end

  def test_a_value_with_nothing_to_translate_never_reaches_the_provider
    assert_equal "", translate("", from: "en", to: "ru")
    assert_nil translate(nil, from: "en", to: "ru")
    assert_empty @provider.requests
  end

  def test_a_missing_source_language_is_detected
    translate("one.", to: "ru")

    assert_equal "en", @provider.requests.first.from
  end

  def test_per_call_options_reach_the_provider_untouched
    translate("one.", from: "en", to: "ru", formality: :less)

    assert_equal({ formality: :less }, @provider.requests.first.options)
  end

  def test_a_second_translation_of_the_same_sentence_is_served_from_cache
    translate("one.", from: "en", to: "ru")
    translate("one.", from: "en", to: "ru")

    assert_equal 1, @provider.requests.size
  end

  def test_only_the_missing_sentences_are_sent
    translate("one. two.", from: "en", to: "ru")
    translate("one. three.", from: "en", to: "ru")

    assert_equal [%w[one. two.], %w[three.]], @provider.requests.map(&:texts)
  end

  # The old check was `respond_to?(:detect)`, satisfied by inheriting the base class's raising stub.
  def test_a_provider_that_cannot_detect_says_so_before_it_is_called
    @provider = BlindProvider.new(TranslationDiff::Configuration.new)

    error = assert_raises(TranslationDiff::Translator::Error) { translate("one.", to: "ru") }

    assert_match(/cannot detect/, error.message)
    assert_match(/blind/, error.message)
    assert_empty @provider.requests
  end

  def test_a_provider_whose_cache_key_is_blank_is_refused_rather_than_sharing_a_namespace
    @provider = NamelessProvider.new(TranslationDiff::Configuration.new)

    error = assert_raises(TranslationDiff::Translator::Error) { translate("one.", from: "en", to: "ru") }

    assert_match(/must define #cache_key/, error.message)
  end

  def test_a_provider_named_for_one_call_overrides_the_configured_one
    configured = RecordingProvider.new(TranslationDiff::Configuration.new)
    TranslationDiff.configure { |c| c.provider = configured }

    assert_equal "ONE.", translate("one.", from: "en", to: "ru")
    assert_empty configured.requests
  end

  def test_without_a_provider_keyword_the_configured_provider_is_used
    TranslationDiff.configure { |c| c.provider = @provider }

    assert_equal "ONE.", TranslationDiff::Translator.new("one.", from: "en", to: "ru").call
    assert_equal 1, @provider.requests.size
  end

  def test_an_object_that_is_not_a_provider_is_refused
    assert_raises(TranslationDiff::InvalidProviderError) do
      TranslationDiff::Translator.new("one.", from: "en", to: "ru", provider: Object.new).call
    end
  end

  def test_a_translation_emits_translate_cache_request_and_rate_limit_events
    recorder = instrumented { |c| c.rate_limiter = FakeRateLimiter.new }
    instrumented_translate("Hello there.")

    assert_equal ALL_EVENT_NAMES, recorder.events.map(&:first).sort
  end

  def test_the_translate_event_carries_languages_provider_and_a_count
    recorder = instrumented
    instrumented_translate(%w[one two])

    payload = payload_for(recorder, "translate")

    assert_equal "en", payload[:from]
    assert_equal "ru", payload[:to]
    assert_equal "recording", payload[:provider]
    assert_equal 2, payload[:values]
  end

  def test_the_cache_event_carries_hit_and_miss_counts
    recorder = instrumented
    instrumented_translate("Hello there.")

    payload = payload_for(recorder, "cache")

    assert_equal 0, payload[:hits]
    assert_equal 1, payload[:misses]
    assert_equal "recording", payload[:provider]
  end

  def test_the_request_event_carries_the_provider_a_batch_size_and_a_character_count
    recorder = instrumented
    instrumented_translate("Hello there.")

    payload = payload_for(recorder, "request")

    assert_equal "recording", payload[:provider]
    assert_equal 1, payload[:batch]
    assert_equal "Hello there.".size, payload[:characters]
  end

  def test_the_rate_limit_event_carries_the_provider_and_a_character_count
    limiter = FakeRateLimiter.new
    recorder = instrumented { |c| c.rate_limiter = limiter }
    instrumented_translate("Hello there.")

    payload = payload_for(recorder, "rate_limit")

    assert_equal "recording", payload[:provider]
    assert_equal "Hello there.".size, payload[:characters]
    assert_equal ["Hello there.".size], limiter.sizes
  end

  # The limiter is consulted with what is about to be sent, before it is sent.
  def test_the_rate_limiter_is_consulted_before_the_provider
    limiter = FakeRateLimiter.new
    recorder = instrumented { |c| c.rate_limiter = limiter }
    instrumented_translate("Hello there.")

    names = recorder.events.map(&:first).select { |name| name.start_with?("rate_limit", "request") }

    assert_equal %w[rate_limit.translation_diff request.translation_diff], names
  end

  def test_no_rate_limit_event_without_a_rate_limiter
    recorder = instrumented
    instrumented_translate("Hello there.")

    refute_includes recorder.events.map(&:first), "rate_limit.translation_diff"
  end

  # A call that returns early reaches no provider and so reports nothing.
  def test_a_call_that_returns_early_emits_no_events
    recorder = instrumented
    instrumented_translate("Hello there.", to: "en")

    assert_empty recorder.events
  end

  ALL_EVENT_NAMES = %w[translate.translation_diff cache.translation_diff
                       request.translation_diff rate_limit.translation_diff
                       usage.translation_diff].sort.freeze

  # A guard that only checked payload content would pass even if an event quietly stopped firing.
  def test_no_payload_ever_contains_the_text_being_translated
    secret = "Zaphod Beeblebrox is president."
    recorder = instrumented { |c| c.rate_limiter = FakeRateLimiter.new }
    instrumented_translate(secret)

    assert_equal ALL_EVENT_NAMES, recorder.events.map(&:first).sort

    serialised = recorder.events.map { |name, payload| "#{name}#{payload}" }.join
    refute_includes serialised, "Zaphod"
    refute_includes serialised, secret
    refute_includes serialised, secret.upcase
  end

  # Captured from the old pipeline: a nested nil has always come back as "" from a call that reached a provider.
  def test_a_nested_nil_collapses_to_an_empty_string
    assert_equal({ a: "ONE.", n: 42, skip: "" },
                 translate({ a: "one.", n: 42, skip: nil }, from: "en", to: "ru"))
    assert_equal ["ONE.", "", 42], translate(["one.", nil, 42], from: "en", to: "ru")
  end

  # And only then: a call with nothing to translate hands the caller's value back exactly as it was given.
  def test_a_nil_survives_a_call_that_translates_nothing
    assert_nil translate(nil, from: "en", to: "ru")
    assert_equal [nil], translate([nil], from: "en", to: "ru")
    assert_equal({ a: nil }, translate({ a: nil }, from: "en", to: "ru"))
  end

  # A subscriber grouping by payload[:to] must not see :ru and "ru" as two different series.
  def test_the_translate_event_reports_languages_as_strings_whatever_the_caller_passed
    recorder = instrumented
    TranslationDiff::Translator.new("Hello there.", from: :en, to: :ru, provider: @provider).call

    payload = payload_for(recorder, "translate")

    assert_equal "en", payload[:from]
    assert_equal "ru", payload[:to]
  end

  # `values` is the size of the document as the caller wrote it, not the number of translatable strings in it.
  def test_the_translate_event_counts_every_leaf_the_caller_wrote
    recorder = instrumented
    instrumented_translate({ a: "one.", n: 42, skip: nil })

    assert_equal 3, payload_for(recorder, "translate")[:values]
  end

  def test_a_value_with_nothing_to_translate_never_resolves_a_provider
    assert_equal 42, TranslationDiff::Translator.new(42, from: "en", to: "ru", provider: Object.new).call
  end

  # A call that hands the caller's value straight back should not need a provider to do it: an app that has
  # configured none at all still gets its value. Configured with something that is not a provider rather than
  # left unset, so resolving one raises whatever the developer has in their environment.
  def test_the_same_language_does_not_even_resolve_a_provider
    TranslationDiff.configure { |c| c.provider = Object.new }

    assert_equal "Hello", TranslationDiff::Translator.new("Hello", from: :ru, to: :ru).call
  end

  def test_a_value_with_nothing_to_translate_does_not_resolve_the_configured_provider_either
    TranslationDiff.configure { |c| c.provider = Object.new }

    assert_equal 42, TranslationDiff::Translator.new(42, from: "en", to: "ru").call
  end

  def test_the_provider_is_logged_once_and_only_when_it_is_resolved
    logger = FakeLogger.new
    TranslationDiff.configure { |c| c.logger = logger }

    translate(42, from: "en", to: "ru")

    assert_empty logger.lines

    translate("one.", from: "en", to: "ru")

    assert_equal 1, logger.lines.size
    assert_match(/RecordingProvider/, logger.lines.first)
  end

  # A nil target used to reach the cache key and die there on #downcase; it is a caller's mistake, not a defect.
  def test_a_missing_target_language_is_refused_by_name
    error = assert_raises(ArgumentError) { translate("one.", from: "en") }

    assert_match(/to:/, error.message)
  end

  # A provider whose languages we ship, driven with a pair it does not do.
  class DeepLDouble < TranslationDiff::Providers::DeepL
    attr_reader :requests

    def translate(request)
      (@requests ||= []) << request
      TranslationDiff::Translation::Response.build(request: request, texts: request.texts.map(&:to_s))
    end

    def cache_key = "deepl"
  end

  def deepl_double
    TranslationDiff.configure { |c| c.deepl_api_key = "test-key" }
    DeepLDouble.new(TranslationDiff.config)
  end

  def test_an_unsupported_pair_raises_before_a_request_is_made
    provider = deepl_double

    error = assert_raises(TranslationDiff::UnsupportedLanguageError) do
      TranslationDiff.translate("Hello there.", from: "en", to: "klingon", provider: provider)
    end

    assert_nil provider.requests
    assert_match(/klingon/, error.message)
    assert_match(/deepl/, error.message)
    assert_match(/assume_supported/, error.message)
  end

  def test_a_supported_pair_goes_through
    assert_equal "Hello there.",
                 TranslationDiff.translate("Hello there.", from: "en", to: "ru", provider: deepl_double)
  end

  def test_the_per_call_escape_lets_an_unlisted_pair_through
    assert_equal "Hello there.",
                 TranslationDiff.translate("Hello there.", from: "en", to: "klingon",
                                                           provider: deepl_double, assume_supported: true)
  end

  def test_the_global_switch_turns_validation_off
    TranslationDiff.configure { |c| c.validate_languages = false }

    assert_equal "Hello there.",
                 TranslationDiff.translate("Hello there.", from: "en", to: "klingon", provider: deepl_double)
  end

  # Reserved, like provider: and config: -- every other keyword is forwarded to the vendor untouched.
  def test_assume_supported_never_reaches_the_provider
    provider = deepl_double
    TranslationDiff.translate("Hello there.", from: "en", to: "ru", provider: provider, assume_supported: true)

    refute_includes provider.requests.first.options.keys, :assume_supported
  end

  def test_a_provider_we_ship_no_data_for_refuses_nothing
    assert_equal "Hello there.",
                 TranslationDiff.translate("Hello there.", from: "en", to: "klingon", provider: :null)
  end

  # ModernMT genuinely translates Persian; it just publishes it under its ISO 639-3 individual code "pes".
  class ModernMTDouble < TranslationDiff::Providers::ModernMT
    def translate(request)
      TranslationDiff::Translation::Response.build(request: request, texts: request.texts.map(&:to_s))
    end

    def cache_key = "modernmt"
  end

  def test_modernmt_translates_a_macrolanguage_it_only_lists_under_its_individual_code
    TranslationDiff.configure { |c| c.modernmt_api_key = "test-key" }
    provider = ModernMTDouble.new(TranslationDiff.config)

    assert_equal "Hello there.",
                 TranslationDiff.translate("Hello there.", from: "en", to: "fa", provider: provider)
  end

  # A provider whose #detect would cost a real request if it were ever reached.
  class ExplodingOnDetectDouble < DeepLDouble
    def detect(_text) = raise "detect must never be called when the target alone is already unsupported"
  end

  def test_an_unsupported_target_is_refused_before_a_provider_is_asked_to_detect
    TranslationDiff.configure { |c| c.deepl_api_key = "test-key" }
    provider = ExplodingOnDetectDouble.new(TranslationDiff.config)

    error = assert_raises(TranslationDiff::UnsupportedLanguageError) do
      TranslationDiff.translate("Hello there.", to: "klingon", provider: provider)
    end

    assert_match(/klingon/, error.message)
  end

  # When `from:` is given the whole pair is already known, so there is nothing to defer: validate it once.
  def test_a_pair_given_up_front_is_validated_exactly_once
    original = TranslationDiff::Languages.method(:supports?)
    calls = 0
    TranslationDiff::Languages.define_singleton_method(:supports?) do |*args, **kwargs|
      calls += 1
      original.call(*args, **kwargs)
    end

    translate("one.", from: "en", to: "ru")

    assert_equal 1, calls
  ensure
    TranslationDiff::Languages.define_singleton_method(:supports?, &original)
  end

  private

  def instrumented
    Recorder.new.tap do |recorder|
      TranslationDiff.configure do |c|
        c.instrumenter = recorder
        yield c if block_given?
      end
    end
  end

  def instrumented_translate(values, from: "en", to: "ru")
    TranslationDiff::Translator.new(values, from: from, to: to, provider: @provider).call
  end

  def payload_for(recorder, event)
    recorder.events.find { |name, _| name == "#{event}.translation_diff" }.last
  end
end
