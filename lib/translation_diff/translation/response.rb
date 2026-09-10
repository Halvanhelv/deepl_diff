# ::build is the one guard over every provider's parse step: a wrong count or a non-String would surface far away.
module TranslationDiff::Translation
  Response = Data.define(:texts, :detected_source, :usage) do
    def self.build(request:, texts:, detected_source: nil, usage: nil)
      ensure_count!(request, texts)
      ensure_strings!(texts)

      # Every provider's text lands here, so the same decoder the input path used runs once, here, on the way back.
      new(texts: texts.map { |text| TranslationDiff::Markup.decode_entities(text) },
          detected_source: detected_source, usage: usage)
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
