# frozen_string_literal: true

# An isolated configuration scope offering the same entry point as the
# TranslationDiff module itself, for multi-tenant applications and
# per-request overrides. Created with TranslationDiff.context.
class TranslationDiff::Context
  attr_reader :config

  def initialize(config)
    @config = config
  end

  def translate(values, from: nil, to: nil, provider: nil, **)
    TranslationDiff::Request.new(
      values, from: from, to: to, provider: provider, config: config, **
    ).call
  end
end
