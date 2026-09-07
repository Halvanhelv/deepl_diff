# frozen_string_literal: true

require "test_helper"

class RequestTest < Minitest::Test
  Translation = Struct.new(:text)
  Detection = Struct.new(:detected_source_language)

  # Records what it was asked to translate so the call can be asserted on,
  # and answers with a canned response.
  class FakeApi
    attr_reader :calls

    def initialize(response, detected: nil)
      @response = response
      @detected = detected
      @calls = []
    end

    def translate(text, from, to, options = {})
      @calls << [text, from, to, options]
      return Detection.new(@detected) if from.nil?

      @response.map { |value| Translation.new(value) }
    end
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

  def teardown
    DeepLDiff.api = nil
    DeepLDiff.cache_store = nil
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

  # The options hash belongs to the caller. Consuming :from and :to out of it
  # broke the second call with the same hash, and blew up outright on a frozen
  # one -- which is what a hash of settings kept in a constant is.
  def test_leaves_the_callers_options_hash_alone
    options = { from: :en, to: :ru }

    DeepLDiff.api = FakeApi.new(["Какая-то строка"])
    DeepLDiff.cache_store = FakeCacheStore.new

    2.times do
      assert_equal "Какая-то строка", DeepLDiff::Request.new("Some string", options).call
    end
    assert_equal({ from: :en, to: :ru }, options)
  end

  def test_accepts_a_frozen_options_hash
    DeepLDiff.api = FakeApi.new(["Какая-то строка"])
    DeepLDiff.cache_store = FakeCacheStore.new

    result = DeepLDiff::Request.new("Some string", { from: :en, to: :ru }.freeze).call

    assert_equal "Какая-то строка", result
  end

  # A detected language comes back as a String while :to is usually a Symbol,
  # so the source == target short circuit never fired and the text was paid
  # for and translated into its own language.
  def test_skips_the_translation_when_the_detected_language_is_the_target
    api = FakeApi.new([], detected: "RU")
    DeepLDiff.api = api
    DeepLDiff.cache_store = FakeCacheStore.new

    result = DeepLDiff::Request.new("привет", { to: :ru }).call

    assert_equal "привет", result
    assert_equal 1, api.calls.size, "only the detection call should be made"
  end

  def test_raises_when_the_api_returns_fewer_translations_than_asked_for
    DeepLDiff.api = FakeApi.new(%w[Один])
    DeepLDiff.cache_store = FakeCacheStore.new

    error = assert_raises(DeepLDiff::Request::Error) do
      DeepLDiff::Request.new({ a: "One", b: "Two" }, { from: :en, to: :ru }).call
    end

    assert_match(/returned 1 translations for 2 values/, error.message)
  end

  # These used to raise NoMethodError on #empty? or TypeError inside Ox.
  UNTRANSLATABLE = [42, :sym, "", "   "].freeze

  UNTRANSLATABLE.each do |value|
    define_method(:"test_passes_through_#{value.inspect.gsub(/\W/, '_')}_untouched") do
      api = FakeApi.new([])
      DeepLDiff.api = api
      DeepLDiff.cache_store = FakeCacheStore.new

      assert_equal value, DeepLDiff::Request.new(value, { from: :en, to: :ru }).call
      assert_empty api.calls
    end
  end

  def test_passes_through_nil_untouched
    api = FakeApi.new([])
    DeepLDiff.api = api
    DeepLDiff.cache_store = FakeCacheStore.new

    assert_nil DeepLDiff::Request.new(nil, { from: :en, to: :ru }).call
    assert_empty api.calls
  end

  # Scalars nested in a structure are passed through too, while nil keeps
  # collapsing to "" the way it always has.
  def test_passes_nested_scalars_through_and_still_blanks_out_nils
    DeepLDiff.api = FakeApi.new(%w[Один])
    DeepLDiff.cache_store = FakeCacheStore.new

    result = DeepLDiff::Request.new({ a: "One", n: 42, skip: nil }, { from: :en, to: :ru }).call

    assert_equal({ a: "Один", n: 42, skip: "" }, result)
  end

  private

  # Translates `values` from :en to :ru against fakes.
  # Returns the translation and the API fake, so the call can be asserted on.
  def translate(values, response)
    api = FakeApi.new(response)
    DeepLDiff.api = api
    DeepLDiff.cache_store = FakeCacheStore.new

    [DeepLDiff::Request.new(values, { from: :en, to: :ru }).call, api]
  end
end
