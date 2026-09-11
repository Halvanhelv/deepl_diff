# An isolated configuration scope with the same entry point as TranslationDiff itself.
class TranslationDiff::Context
  attr_reader :config

  def initialize(config)
    @config = config
  end

  def translate(values, from: nil, to: nil, provider: nil, assume_supported: false, **)
    TranslationDiff::Translator.new(
      values, from: from, to: to, provider: provider, config: config,
              assume_supported: assume_supported, **
    ).call
  end

  # Answers what #translate would do to `values` under this context's own configuration, without calling it.
  def preview(values, from: nil, to: nil, provider: nil, assume_supported: false, **)
    TranslationDiff::Previewer.new(
      values, from: from, to: to, provider: provider, config: config,
              assume_supported: assume_supported, **
    ).call
  end
end
