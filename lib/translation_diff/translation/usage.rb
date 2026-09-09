# frozen_string_literal: true

# What one provider call cost. `characters` is what we sent and is always
# known; `billed_characters` is what the provider says it charged for and is
# nil for the providers that do not report it. `tokens` and `model` are nil
# for every machine-translation provider and exist so that an LLM-backed
# provider needs no new type.
module TranslationDiff::Translation
  Usage = Data.define(:characters, :billed_characters, :tokens, :model) do
    def initialize(characters:, billed_characters: nil, tokens: nil, model: nil)
      super
    end
  end
end
