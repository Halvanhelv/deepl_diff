# frozen_string_literal: true

# What the pipeline asks a provider for. `from` may be nil, which means the
# provider should detect the source language. `options` carries the per-call
# provider options the caller passed to TranslationDiff.translate, untouched.
module TranslationDiff::Translation
  Request = Data.define(:texts, :from, :to, :options) do
    def initialize(texts:, from:, to:, options: {})
      super
    end
  end
end
