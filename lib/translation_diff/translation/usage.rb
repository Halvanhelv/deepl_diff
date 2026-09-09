# frozen_string_literal: true

# `billed_characters` is nil, not 0, when a provider doesn't report it; `tokens`/`model` exist for LLM providers.
module TranslationDiff::Translation
  Usage = Data.define(:characters, :billed_characters, :tokens, :model) do
    def initialize(characters:, billed_characters: nil, tokens: nil, model: nil)
      super
    end
  end
end
