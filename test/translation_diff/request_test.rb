# frozen_string_literal: true

require "test_helper"

class RequestTest < ConfiguredTest
  # Records what it was asked to translate, and answers with a canned response.
  class FakeApi < TranslationDiff::Provider
    CAPABILITIES = TranslationDiff::Capabilities.new(
      max_request_size: 1_000_000, max_batch_size: 1_000_000, max_text_size: nil,
      html: :none, notranslate: false, detects_language: true, reports_billing: false
    ).freeze

    def self.capabilities = CAPABILITIES

    attr_reader :calls

    def initialize(response, detected: nil)
      super(TranslationDiff::Configuration.new)
      @response = response
      @detected = detected
      @calls = []
    end

    def translate(request)
      @calls << [request.texts, request.from, request.to, request.options]
      TranslationDiff::Translation::Response.build(
        request: request, texts: @response.shift(request.texts.size)
      )
    end

    def detect(text)
      @calls << [:detect, text]
      @detected
    end

    def cache_key = "fake"
  end

  # Proves the generalisation took effect: capabilities capping the batch at one must change the chunking.
  class NarrowBatchApi < FakeApi
    def self.capabilities
      TranslationDiff::Capabilities.new(
        max_request_size: 1_000_000, max_batch_size: 1, max_text_size: nil,
        html: :none, notranslate: false, detects_language: true, reports_billing: false
      )
    end
  end

  # Registered under :echo to exercise resolving a provider by name through the registry.
  class EchoProvider < TranslationDiff::Provider
    def self.capabilities
      TranslationDiff::Capabilities.new(
        max_request_size: 1_000_000, max_batch_size: 1_000_000, max_text_size: nil,
        html: :none, notranslate: false, detects_language: false, reports_billing: false
      )
    end

    def translate(request) = TranslationDiff::Translation::Response.build(request: request, texts: request.texts)

    def cache_key = "echo"
  end
  TranslationDiff::Providers.register(:echo, EchoProvider) unless TranslationDiff::Providers.registered?(:echo)

  # Always misses, so every value reaches the API.
  class FakeCacheStore
    attr_reader :writes

    def initialize
      @writes = {}
    end

    def read_multi(keys)
      [nil] * keys.size
    end

    def write(key, value)
      @writes[key] = value
    end
  end

  # An object assigned straight to `config.provider` never passed through the registry's stamping.
  class NamelessApi < FakeApi
    def cache_key = ""
  end

  # A whitespace-only key is just as blank as an empty one; it must not slip past the guard.
  class WhitespaceNamedApi < FakeApi
    def cache_key = "   "
  end

  # Proves the all-cached short circuit: serving a translation from cache without calling the adapter at all.
  class AllCachedStore
    def initialize(responses)
      @responses = responses
    end

    def read_multi(keys)
      @responses.first(keys.size)
    end

    def write(*)
      raise "should not write when nothing was missing"
    end
  end

  def test_translates_a_plain_string
    result, api = translate("Some string", ["Какая-то строка"])

    assert_equal "Какая-то строка", result
    assert_equal [[["Some string"], :en, :ru, {}]], api.calls
  end

  def test_translates_the_values_of_a_flat_hash
    result, api = translate({ title: "One", description: "Two" }, %w[Один Два])

    assert_equal({ title: "Один", description: "Два" }, result)
    assert_equal [[%w[One Two], :en, :ru, {}]], api.calls
  end

  def test_translates_nested_values_and_blanks_out_nils
    values = { title: "One", more: { description: "Two" }, skip: nil }

    result, api = translate(values, %w[Один Два])

    assert_equal({ title: "Один", more: { description: "Два" }, skip: "" }, result)
    assert_equal [[%w[One Two], :en, :ru, {}]], api.calls
  end

  MARKUP_VALUES = {
    title: "One",
    more: {
      description: "<b>Black</b>",
      color: %(So   <font size='35'><script>One</script><!-- Test -->Red\n</font> that)
    }
  }.freeze

  MARKUP_TRANSLATED = {
    title: "Один",
    more: {
      description: "<b>Черный</b>",
      color: %(Что   <font size='35'><script>One</script><!-- Test -->Кра\n</font> что)
    }
  }.freeze

  def test_translates_text_around_markup_and_leaves_the_markup_alone
    result, api = translate(MARKUP_VALUES, %w[Один Черный Что Кра что])

    assert_equal MARKUP_TRANSLATED, result
    assert_equal [[%w[One Black So Red that], :en, :ru, {}]], api.calls
  end

  # True of the public interface, but not new: 2.1.0 already protected the caller's hash by dup-ing it.
  def test_repeated_calls_leave_the_callers_options_hash_alone
    options = { from: :en, to: :ru }

    configure_with(FakeApi.new(["Какая-то строка", "Какая-то строка"]))

    2.times do
      assert_equal "Какая-то строка", TranslationDiff.translate("Some string", **options)
    end
    assert_equal({ from: :en, to: :ru }, options)
  end

  # The initializer now declares one positional parameter, so a positional options hash is no longer accepted.
  def test_the_positional_options_hash_is_no_longer_accepted
    assert_raises(ArgumentError) do
      TranslationDiff::Request.new("text", { from: :en, to: :ru })
    end
  end

  # A detected language is a String while :to is usually a Symbol -- without casecmp? this never short-circuits.
  def test_skips_the_translation_when_the_detected_language_is_the_target
    api = FakeApi.new([], detected: "RU")
    configure_with(api)

    result = TranslationDiff::Request.new("привет", to: :ru).call

    assert_equal "привет", result
    assert_equal [[:detect, "привет"]], api.calls
  end

  # Chunker's limits used to come from two provider methods; they now come from the declared capabilities.
  # rubocop:disable-next Metrics/AbcSize, Metrics/MethodLength
  def test_chunking_uses_the_providers_declared_capabilities
    narrow = Class.new(TranslationDiff::Provider) do
      def self.capabilities
        TranslationDiff::Capabilities.new(
          max_request_size: 20, max_batch_size: 1, max_text_size: nil,
          html: :none, notranslate: false, detects_language: false, reports_billing: false
        )
      end

      attr_reader :batches

      def initialize(config)
        super
        @batches = []
      end

      def translate(request)
        @batches << request.texts
        TranslationDiff::Translation::Response.build(request: request, texts: request.texts)
      end

      def cache_key = "narrow"
    end

    provider = narrow.new(TranslationDiff::Configuration.new)
    TranslationDiff.translate("One. Two. Three.", from: "en", to: "ru", provider: provider)

    assert(provider.batches.all? { |batch| batch.size == 1 },
           "expected one text per request, got #{provider.batches.inspect}")
  end

  # The old check was `respond_to?(:detect)`, satisfied by inheriting the base class's raising stub.
  def test_a_provider_that_cannot_detect_says_so_before_it_is_called
    error = assert_raises(TranslationDiff::Request::Error) do
      TranslationDiff.translate("Some text.", to: "ru", provider: :null)
    end

    assert_match(/cannot detect/, error.message)
    assert_match(/null/, error.message)
  end

  # The count check now lives in Translation::Response.build, so it holds for every provider, hence ResponseError.
  def test_raises_when_the_api_returns_fewer_translations_than_asked_for
    configure_with(FakeApi.new(%w[Один]))

    error = assert_raises(TranslationDiff::ResponseError) do
      TranslationDiff::Request.new({ a: "One", b: "Two" }, from: :en, to: :ru).call
    end

    assert_match(/returned 1 translations for 2 values/, error.message)
  end

  # These used to raise NoMethodError on #empty? or TypeError inside Ox.
  UNTRANSLATABLE = [42, :sym, "", "   "].freeze

  UNTRANSLATABLE.each do |value|
    define_method(:"test_passes_through_#{value.inspect.gsub(/\W/, '_')}_untouched") do
      api = FakeApi.new([])
      configure_with(api)

      assert_equal value, TranslationDiff::Request.new(value, from: :en, to: :ru).call
      assert_empty api.calls
    end
  end

  def test_passes_through_nil_untouched
    api = FakeApi.new([])
    configure_with(api)

    assert_nil TranslationDiff::Request.new(nil, from: :en, to: :ru).call
    assert_empty api.calls
  end

  # Scalars nested in a structure are passed through too, while nil keeps collapsing to "".
  def test_passes_nested_scalars_through_and_still_blanks_out_nils
    configure_with(FakeApi.new(%w[Один]))

    result = TranslationDiff::Request.new({ a: "One", n: 42, skip: nil }, from: :en, to: :ru).call

    assert_equal({ a: "Один", n: 42, skip: "" }, result)
  end

  # Proves the generalisation took effect: a provider declaring tiny limits must change the batching.
  def test_batches_according_to_the_limits_the_adapter_declares
    api = NarrowBatchApi.new(%w[Один Два])
    configure_with(api)

    TranslationDiff::Request.new({ a: "One", b: "Two" }, from: :en, to: :ru).call

    assert_equal 2, api.calls.size, "one call per text at a batch size of 1"
  end

  # The only Request-level test exercising a cache hit; every other fake store in this file always misses.
  def test_serves_a_translation_from_cache_without_calling_the_adapter
    api = FakeApi.new([])
    configure_with(api, AllCachedStore.new(["Какая-то строка"]))

    result = TranslationDiff::Request.new("Some string", from: :en, to: :ru).call

    assert_equal "Какая-то строка", result
    assert_empty api.calls
  end

  # `provider:` picks the provider for one call; the configured provider is left untouched and unused.
  def test_the_provider_keyword_overrides_the_configured_provider_for_one_call
    api = FakeApi.new(%w[Один])
    configure_with(api)

    result = TranslationDiff::Request.new("One", from: :en, to: :ru, provider: :echo).call

    assert_equal "One", result
    assert_empty api.calls
  end

  # An empty cache-key segment would put this provider's translations in every other provider's namespace.
  def test_a_provider_whose_cache_key_is_empty_is_refused_rather_than_sharing_a_namespace
    configure_with(NamelessApi.new(%w[Один]))

    error = assert_raises(TranslationDiff::Request::Error) do
      TranslationDiff::Request.new("One", from: :en, to: :ru).call
    end

    assert_match(/must define #cache_key/, error.message)
  end

  def test_a_provider_whose_cache_key_is_whitespace_is_refused_rather_than_sharing_a_namespace
    configure_with(WhitespaceNamedApi.new(%w[Один]))

    error = assert_raises(TranslationDiff::Request::Error) do
      TranslationDiff::Request.new("One", from: :en, to: :ru).call
    end

    assert_match(/must define #cache_key/, error.message)
  end

  private

  # Returns the translation and the API fake, so the call can be asserted on.
  def translate(values, response)
    api = FakeApi.new(response)
    configure_with(api)

    [TranslationDiff::Request.new(values, from: :en, to: :ru).call, api]
  end

  # An object assigned to `provider` or `cache` is used as-is, so a fake goes in exactly where a name would.
  def configure_with(api, store = FakeCacheStore.new)
    TranslationDiff.configure do |config|
      config.provider = api
      config.cache = store
    end
  end
end
