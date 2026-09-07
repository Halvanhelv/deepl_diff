# frozen_string_literal: true

require "test_helper"
require "support/adapter_contract"

class DeepLAdapterTest < Minitest::Test
  include AdapterContract

  Translation = Struct.new(:text)
  Detection = Struct.new(:detected_source_language)

  # Stands in for the deepl-rb client. The gem does not depend on it.
  class FakeClient
    attr_reader :calls

    def initialize(detected: "DE")
      @detected = detected
      @calls = []
    end

    def translate(text, from, to, options = {})
      @calls << [text, from, to, options]
      return Detection.new(@detected) if from.nil?

      Array(text).map { |value| Translation.new("T:#{value}") }
    end
  end

  def adapter(client = FakeClient.new)
    TranslationDiff::Adapters::DeepL.new(client)
  end

  def test_translate_unwraps_the_text_of_each_result
    assert_equal %w[T:one T:two], adapter.translate(%w[one two], from: :en, to: :ru)
  end

  def test_translate_passes_provider_options_through
    client = FakeClient.new

    adapter(client).translate(%w[one], from: :en, to: :ru, formality: :less)

    assert_equal [[%w[one], :en, :ru, { formality: :less }]], client.calls
  end

  def test_detect_downcases_the_language
    assert_equal "de", adapter(FakeClient.new(detected: "DE")).detect("etwas")
  end

  # DeepL has no detection endpoint, so the adapter supplies a target of its
  # own rather than making the caller invent one.
  def test_detect_supplies_its_own_target_language
    client = FakeClient.new

    adapter(client).detect("etwas")

    assert_equal [["etwas", nil, "EN", {}]], client.calls
  end

  def test_cache_key_identifies_the_provider
    assert_equal "deepl", adapter.cache_key
  end
end
