# frozen_string_literal: true

# ::build checks the count: fewer texts than requested would shift nils in and surface as a distant NoMethodError.
module TranslationDiff::Translation
  Response = Data.define(:texts, :detected_source, :usage) do
    def self.build(request:, texts:, detected_source: nil, usage: nil)
      if texts.size != request.texts.size
        raise TranslationDiff::ResponseError,
              "Provider returned #{texts.size} translations for #{request.texts.size} values"
      end

      new(texts: texts, detected_source: detected_source, usage: usage)
    end
  end
end
