require "test_helper"

class PreviewerTest < ConfiguredTest
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
      TranslationDiff::Translation::Response.build(request: request, texts: request.texts.map(&:upcase))
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

  # Counts every write the pipeline attempts, whichever contract it uses, so "writes nothing" has real evidence.
  class WriteTrackingStore
    attr_reader :write_calls

    def initialize
      @inner = TranslationDiff::MemoryCacheStore.new(max_size: 100)
      @write_calls = 0
    end

    def read_multi(keys) = @inner.read_multi(keys)

    def write_multi(pairs)
      @write_calls += 1
      @inner.write_multi(pairs)
    end
  end

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
    @provider = RecordingProvider.new(TranslationDiff::Configuration.new)
    TranslationDiff.configure { |c| c.cache = :memory }
  end

  def preview(values, **)
    TranslationDiff.preview(values, provider: @provider, **)
  end

  def test_a_document_nothing_has_cached_counts_every_sentence_as_sendable
    result = preview("One. Two.", from: "en", to: "ru")

    assert_equal 2, result.sendable_sentences
    assert_equal 0, result.cached_sentences
    assert_equal "One.Two.".size, result.sendable_characters
    assert_equal "One.Two.".size, result.characters
  end

  # The denominator a fully-cached call still needs: sendable_characters alone would report 0 of nothing,
  # leaving no way to say "this call would send 0 of 8 characters" rather than "there was nothing to send".
  def test_after_translating_nothing_is_left_to_send
    TranslationDiff.translate("One. Two.", from: "en", to: "ru", provider: @provider)

    result = preview("One. Two.", from: "en", to: "ru")

    assert_equal 0, result.sendable_sentences
    assert_equal 2, result.cached_sentences
    assert_equal 0, result.sendable_characters
    assert_equal "One.Two.".size, result.characters
  end

  # This is the property the whole thing exists for: an edit to one sentence sends exactly that sentence.
  def test_editing_one_sentence_sends_exactly_that_sentence
    TranslationDiff.translate("One. Two.", from: "en", to: "ru", provider: @provider)

    result = preview("One. Three.", from: "en", to: "ru")

    assert_equal 1, result.sendable_sentences
    assert_equal 1, result.cached_sentences
    assert_equal "Three.".size, result.sendable_characters
  end

  # The strongest test available: it pins the preview to the pipeline, not to an idea of the pipeline.
  def test_the_previews_counts_equal_what_translate_then_reports_through_the_cache_event
    TranslationDiff.translate("One. Two.", from: "en", to: "ru", provider: @provider)
    predicted = preview("One. Three.", from: "en", to: "ru")

    recorder = Recorder.new
    TranslationDiff.configure { |c| c.instrumenter = recorder }
    TranslationDiff.translate("One. Three.", from: "en", to: "ru", provider: @provider)
    payload = recorder.events.find { |name, _| name == "cache.translation_diff" }.last

    assert_equal predicted.sendable_sentences, payload[:misses]
    assert_equal predicted.cached_sentences, payload[:hits]
  end

  # The strongest available check that a preview's total and a translate call's own report of its size agree.
  def test_the_previews_total_characters_equals_what_the_translate_event_reports
    predicted = preview("One. Two.", from: "en", to: "ru")

    recorder = Recorder.new
    TranslationDiff.configure { |c| c.instrumenter = recorder }
    TranslationDiff.translate("One. Two.", from: "en", to: "ru", provider: @provider)
    payload = recorder.events.find { |name, _| name == "translate.translation_diff" }.last

    assert_equal predicted.characters, payload[:characters]
  end

  def test_an_explicit_provider_and_the_configured_one_agree
    TranslationDiff.configure { |c| c.provider = @provider }

    from_config = TranslationDiff.preview("One. Two.", from: "en", to: "ru")
    explicit = TranslationDiff.preview("One. Two.", from: "en", to: "ru", provider: @provider)

    assert_equal from_config, explicit
  end

  def test_nothing_is_written
    tracker = WriteTrackingStore.new
    TranslationDiff.configure { |c| c.cache = tracker }
    TranslationDiff.translate("One. Two.", from: "en", to: "ru", provider: @provider)
    writes_after_translate = tracker.write_calls

    preview("One. Two.", from: "en", to: "ru")
    preview("One. Three.", from: "en", to: "ru")

    assert_equal writes_after_translate, tracker.write_calls
  end

  def test_the_same_language_needs_no_provider_and_sends_nothing
    result = TranslationDiff.preview("One.", from: "en", to: "en", provider: Object.new)

    assert_equal 0, result.sendable_sentences
  end

  def test_a_value_with_nothing_to_preview_resolves_no_provider
    result = TranslationDiff.preview("", from: "en", to: "ru", provider: Object.new)

    assert_equal 0, result.sendable_sentences
  end

  # Detection is a paid request; a preview never makes one, so it says so instead of guessing.
  def test_a_missing_source_language_is_refused_when_the_provider_would_have_to_detect_it
    error = assert_raises(TranslationDiff::Previewer::Error) { preview("One.", to: "ru") }

    assert_match(/paid request/, error.message)
    assert_match(/from:/, error.message)
  end

  def test_a_provider_that_cannot_detect_says_so_before_it_is_called
    @provider = BlindProvider.new(TranslationDiff::Configuration.new)

    error = assert_raises(TranslationDiff::Previewer::Error) { preview("One.", to: "ru") }

    assert_match(/cannot detect/, error.message)
  end

  def test_a_missing_target_language_is_refused_by_name
    error = assert_raises(ArgumentError) { preview("One.", from: "en") }

    assert_match(/to:/, error.message)
  end

  def test_per_call_options_change_the_cache_key_the_same_way_translate_does
    TranslationDiff.translate("One.", from: "en", to: "ru", provider: @provider, formality: :less)

    default_options = preview("One.", from: "en", to: "ru")
    same_options = preview("One.", from: "en", to: "ru", formality: :less)

    assert_equal 1, default_options.sendable_sentences
    assert_equal 0, same_options.sendable_sentences
  end

  # Same guard Translator uses, shared through TranslationDiff::Providers.resolve.
  def test_a_provider_whose_cache_key_is_blank_is_refused_rather_than_lying_about_the_cache
    @provider = NamelessProvider.new(TranslationDiff::Configuration.new)

    error = assert_raises(TranslationDiff::InvalidProviderError) { preview("One.", from: "en", to: "ru") }

    assert_match(/must define #cache_key/, error.message)
  end

  def test_no_preview_error_message_carries_the_text_being_previewed
    secret = "Zaphod Beeblebrox is president."

    error = assert_raises(TranslationDiff::Previewer::Error) { preview(secret, to: "ru") }

    refute_includes error.message, secret
  end
end
