# ::build is the one guard over every provider's parse step: a wrong count or a non-String would surface far away.
module TranslationDiff::Translation
  Response = Data.define(:texts, :detected_source, :usage) do
    def self.build(request:, texts:, detected_source: nil, usage: nil)
      ensure_count!(request, texts)
      ensure_strings!(texts)

      # Every provider's text lands here, so it takes the same path @core did: escaped, then decoded once, so an
      # entity a provider genuinely sent survives as the entity it is rather than the bare character it decodes to.
      new(texts: texts.map { |text| decoded(text) }, detected_source: detected_source, usage: usage)
    end

    def self.decoded(text)
      TranslationDiff::Markup.decode_entities(TranslationDiff::Markup.escape_bare_angles(text))
    end

    def self.ensure_count!(request, texts)
      return if texts.size == request.texts.size

      raise TranslationDiff::ResponseError,
            "Provider returned #{texts.size} translations for #{request.texts.size} values"
    end

    # The class, never the value: the value is either the customer's text or the provider's own error object.
    def self.ensure_strings!(texts)
      index = texts.index { |text| !text.is_a?(String) }
      return if index.nil?

      raise TranslationDiff::ResponseError,
            "Provider returned #{texts[index].class} rather than a translation at position " \
            "#{index} of #{texts.size}. A response can be well-formed and still carry no " \
            "translation for one input -- a per-string failure inside a batch that answered 200."
    end
  end
end
