# Shared by Translator and Previewer: turning values into a passage, checking a language pair is
# supported, and opening the cache -- the parts that answer the same question either way a call is made.
module TranslationDiff::CallPreparation
  # `include` ignores the includer's own `private` keyword, so visibility has to be declared here.

  private

  # opaque_elements comes from the configuration this call is actually using -- a context's own setting must
  # never fall back to Passage's global default.
  def passage(string)
    TranslationDiff::Passage.new(string, segmenter: config.segmenter_instance, language: @from,
                                         opaque_elements: config.opaque_elements)
  end

  # A detected language arrives as a String while `to:` is usually a Symbol, so neither type nor case can be assumed.
  def same_language?(from) = from.to_s.casecmp?(@to.to_s)

  # nil means we ship no data for this provider, and silence is not evidence of absence.
  def ensure_supported!(provider, from)
    return if @assume_supported || !config.validate_languages

    supported = TranslationDiff::Languages.supports?(provider.cache_key, from: from, to: @to)
    return if supported.nil? || supported

    raise TranslationDiff::UnsupportedLanguageError,
          "Provider #{provider.cache_key} does not translate #{pair_description(from)}. If it does " \
          "now, pass `assume_supported: true` for this call, or set " \
          "`config.validate_languages = false`, and run `rake languages:refresh`."
  end

  def pair_description(from) = from.nil? ? "to #{@to}" : "#{from} to #{@to}"

  # The refusal every caller uses when a provider cannot detect at all; error_class and verb are the only
  # per-caller bits -- Previewer raises a second, stricter refusal of its own even when this one passes.
  def ensure_detects_language!(provider, error_class, verb)
    return if provider.class.capabilities.detects_language?

    raise error_class, "Provider #{provider.cache_key} cannot detect the source language. Pass `from:` " \
                       "with the source language code of the values you are #{verb}."
  end

  # Reads and writes go through the same cache key format either way, so a hit for one is a hit for the other.
  def cache_for(provider, from)
    TranslationDiff::SentenceCache.new(store: config.cache_store, provider: provider.cache_key,
                                       from: from, to: @to, options: @options)
  end
end
