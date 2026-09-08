# frozen_string_literal: true

# Emits events to whatever the application configured as its instrumenter --
# ActiveSupport::Notifications satisfies the interface as-is. When nothing is
# configured, #instrument yields (if given a block) and returns, so call
# sites never branch on whether instrumentation is on.
#
# Payloads carry counts, language codes and provider names. They never carry
# the text being translated, its translation, or a credential: this library
# handles other people's content, and an instrumenter usually writes
# somewhere that content must not go.
module TranslationDiff::Instrumentation
  SUFFIX = ".translation_diff"

  # A point event (no block) reports a fact that already happened -- a cache
  # hit/miss tally, say -- rather than wrapping work, so it only yields when
  # a block was actually given.
  def instrument(name, payload = {})
    instrumenter = config.instrumenter
    return yield if instrumenter.nil? && block_given?
    return if instrumenter.nil?

    instrumenter.instrument("#{name}#{SUFFIX}", payload) { yield if block_given? }
  end

  def log(message)
    config.logger&.debug { "[translation_diff] #{message}" }
  end
end
