# frozen_string_literal: true

# The executable form of the provider contract; anything that passes can be registered and reached via translate.
module ProviderContract
  def translation_request(texts, from: :en, to: :ru, **options)
    TranslationDiff::Translation::Request.new(texts: texts, from: from, to: to, options: options)
  end

  def test_it_inherits_the_provider_base_class
    assert_kind_of TranslationDiff::Provider, provider
  end

  def test_translate_returns_one_string_per_input
    response = provider.translate(translation_request(%w[one two three]))

    assert_equal 3, response.texts.size
    response.texts.each { |value| assert_kind_of String, value }
  end

  def test_translate_preserves_order
    texts = %w[first second third]
    individually = texts.map { |text| provider.translate(translation_request([text])).texts.first }
    batched = provider.translate(translation_request(texts)).texts

    assert_equal individually, batched
  end

  def test_its_capabilities_are_sane
    capabilities = provider.class.capabilities

    assert_operator capabilities.max_request_size, :>, 0
    assert_operator capabilities.max_batch_size, :>, 0
    assert_includes [true, false], capabilities.notranslate?
  end

  # Google and DeepL both shipped with this broken, in different ways, before the capability existed.
  def test_notranslate_is_only_claimed_with_an_html_mode
    capabilities = provider.class.capabilities

    assert capabilities.html?, "claims notranslate without an html mode" if capabilities.notranslate?
  end
end
