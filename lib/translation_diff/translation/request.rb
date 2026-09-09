# frozen_string_literal: true

# What the pipeline asks a provider for; `from` nil means the provider should detect the source language.
module TranslationDiff::Translation
  Request = Data.define(:texts, :from, :to, :options) do
    def initialize(texts:, from:, to:, options: {})
      super
    end
  end
end
