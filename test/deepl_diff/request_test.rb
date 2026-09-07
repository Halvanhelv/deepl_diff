# frozen_string_literal: true

require "test_helper"

class RequestTest < Minitest::Test
  Translation = Struct.new(:text)

  # Records what it was asked to translate so the call can be asserted on,
  # and answers with a canned response.
  class FakeApi
    attr_reader :calls

    def initialize(response)
      @response = response
      @calls = []
    end

    def translate(text, from, to, options = {})
      @calls << [text, from, to, options]
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
