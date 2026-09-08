# frozen_string_literal: true

require "test_helper"

class RequestTest < ConfiguredTest
  # A minimal adapter. Records what it was asked to translate so the call
  # can be asserted on, and answers with a canned response.
  class FakeApi
    attr_reader :calls, :max_request_size, :max_batch_size

    def initialize(response, detected: nil, max_request_size: 1_000_000, max_batch_size: 1_000_000)
      @response = response
      @detected = detected
      @max_request_size = max_request_size
      @max_batch_size = max_batch_size
      @calls = []
    end

    def translate(texts, from:, to:, **options)
      @calls << [texts, from, to, options]
      @response.shift(texts.size)
    end

    def detect(text)
      @calls << [:detect, text]
      @detected
    end

    def cache_key = "fake"
  end

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

  # A provider object assigned straight to `config.provider` never passed
  # through the registry, so nothing stamped it with a name. This one defines
  # its own #cache_key and returns an empty segment from it, which is the case
  # TranslationDiff::Providers::Naming cannot catch.
  class NamelessApi < FakeApi
    def cache_key = ""
  end

  # Already has every key cached, regardless of what it is asked for. Proves
  # the all-cached short circuit in Request#chunks_translated: the gem's
  # headline behaviour is serving a translation from cache without calling
  # the adapter at all.
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

  # True of the public interface, but not new: 2.1.0 already protected the
  # caller's hash from mutation by dup-ing it in the initializer. Keyword
  # arguments keep that guarantee for a different reason (a fresh hash per
  # call), but this test alone cannot tell the two implementations apart.
  def test_repeated_calls_leave_the_callers_options_hash_alone
    options = { from: :en, to: :ru }

    configure_with(FakeApi.new(["Какая-то строка", "Какая-то строка"]))

    2.times do
      assert_equal "Какая-то строка", TranslationDiff.translate("Some string", **options)
    end
    assert_equal({ from: :en, to: :ru }, options)
  end

  # This is what actually changed: the initializer declares one positional
  # parameter now, so a single positional options hash -- which is what every
  # pre-task caller passed -- is no longer accepted.
  def test_the_positional_options_hash_is_no_longer_accepted
    assert_raises(ArgumentError) do
      TranslationDiff::Request.new("text", { from: :en, to: :ru })
    end
  end

  # A detected language comes back as a String while :to is usually a Symbol,
  # so the source == target short circuit never fired and the text was paid
  # for and translated into its own language.
  def test_skips_the_translation_when_the_detected_language_is_the_target
    api = FakeApi.new([], detected: "RU")
    configure_with(api)

    result = TranslationDiff::Request.new("привет", to: :ru).call

    assert_equal "привет", result
    assert_equal [[:detect, "привет"]], api.calls
  end

  def test_raises_when_from_is_missing_and_the_adapter_cannot_detect
    configure_with(TranslationDiff::Providers::Null.new)

    error = assert_raises(TranslationDiff::Request::Error) do
      TranslationDiff::Request.new("text", to: :ru).call
    end

    assert_match(/cannot detect/, error.message)
  end

  def test_raises_when_the_api_returns_fewer_translations_than_asked_for
    configure_with(FakeApi.new(%w[Один]))

    error = assert_raises(TranslationDiff::Request::Error) do
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

  # Scalars nested in a structure are passed through too, while nil keeps
  # collapsing to "" the way it always has.
  def test_passes_nested_scalars_through_and_still_blanks_out_nils
    configure_with(FakeApi.new(%w[Один]))

    result = TranslationDiff::Request.new({ a: "One", n: 42, skip: nil }, from: :en, to: :ru).call

    assert_equal({ a: "Один", n: 42, skip: "" }, result)
  end

  # Proves the generalisation took effect rather than merely being
  # described: an adapter declaring tiny limits must change the batching.
  def test_batches_according_to_the_limits_the_adapter_declares
    api = FakeApi.new(%w[Один Два], max_batch_size: 1)
    configure_with(api)

    TranslationDiff::Request.new({ a: "One", b: "Two" }, from: :en, to: :ru).call

    assert_equal 2, api.calls.size, "one call per text at a batch size of 1"
  end

  # Every fake cache store elsewhere in this file always misses, so this is
  # the only Request-level test exercising a cache hit: a translation served
  # from the store without ever reaching the adapter.
  def test_serves_a_translation_from_cache_without_calling_the_adapter
    api = FakeApi.new([])
    configure_with(api, AllCachedStore.new(["Какая-то строка"]))

    result = TranslationDiff::Request.new("Some string", from: :en, to: :ru).call

    assert_equal "Какая-то строка", result
    assert_empty api.calls
  end

  # `provider:` picks the provider for one call. A name is built through the
  # registry against this call's configuration; the configured provider is
  # left untouched and unused.
  def test_the_provider_keyword_overrides_the_configured_provider_for_one_call
    api = FakeApi.new(%w[Один])
    configure_with(api)

    result = TranslationDiff::Request.new("One", from: :en, to: :ru, provider: :null).call

    assert_equal "One", result
    assert_empty api.calls
  end

  # An empty cache-key segment would put this provider's translations in the
  # same namespace as every other provider's, and a caller would be served
  # another service's answer. Refusing is the only safe response.
  def test_a_provider_whose_cache_key_is_empty_is_refused_rather_than_sharing_a_namespace
    configure_with(NamelessApi.new(%w[Один]))

    error = assert_raises(TranslationDiff::Request::Error) do
      TranslationDiff::Request.new("One", from: :en, to: :ru).call
    end

    assert_match(/must define #cache_key/, error.message)
  end

  private

  # Translates `values` from :en to :ru against fakes.
  # Returns the translation and the API fake, so the call can be asserted on.
  def translate(values, response)
    api = FakeApi.new(response)
    configure_with(api)

    [TranslationDiff::Request.new(values, from: :en, to: :ru).call, api]
  end

  # The two collaborators every test here needs, assigned as configuration
  # options. An object assigned to `provider` or `cache` is used as-is, so a
  # fake goes in exactly where a registered name would.
  def configure_with(api, store = FakeCacheStore.new)
    TranslationDiff.configure do |config|
      config.provider = api
      config.cache = store
    end
  end
end
