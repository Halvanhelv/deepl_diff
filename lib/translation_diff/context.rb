# An isolated configuration scope with the same entry point as TranslationDiff itself.
class TranslationDiff::Context
  attr_reader :config

  def initialize(config)
    @config = config
  end

  def translate(values, from: nil, to: nil, provider: nil, **)
    TranslationDiff::Translator.new(
      values, from: from, to: to, provider: provider, config: config, **
    ).call
  end
end
