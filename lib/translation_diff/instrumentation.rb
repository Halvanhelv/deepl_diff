# Payloads carry counts, language codes and provider names -- never the text, its translation, or a credential.
module TranslationDiff::Instrumentation
  SUFFIX = ".translation_diff".freeze

  # `include` ignores the includer's own `private` keyword, so visibility has to be declared here.
  private

  # A point event (no block) reports a fact that already happened, e.g. a cache hit/miss tally.
  def instrument(name, payload = {})
    instrumenter = config.instrumenter
    return yield if instrumenter.nil? && block_given?
    return if instrumenter.nil?

    instrumenter.instrument("#{name}#{SUFFIX}", payload) { yield if block_given? }
  end

  def log(message)
    config.logger&.debug { "[translation_diff] #{message}" }
  end

  # For the things an operator must see at a production log level; carries no more content than #log does.
  def warn_log(message)
    config.logger&.warn { "[translation_diff] #{message}" }
  end
end
