# frozen_string_literal: true

# What a provider hands back. Built through ::build, which is the only place
# the count is checked: a response with fewer texts than the request shifts
# nils into the results, and they surface much later as a NoMethodError far
# from the provider that caused them.
#
# The check lives here rather than in a base-class method so that it holds
# for every provider, including ones that override #translate outright
# instead of using the HTTP seams.
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
