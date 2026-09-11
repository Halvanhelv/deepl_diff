# Answers what #translate would send and find cached, using the same segmenter, cache key and provider
# resolution translate uses -- without calling the provider or writing anything. Detection is a paid request
# this method never makes, so a nil `from:` for a provider that must detect the language is refused, not guessed at.
class TranslationDiff::Previewer
  # Its own class, so rescuing a preview that cannot be answered cannot also swallow a cache or provider failure.
  class Error < TranslationDiff::Error; end

  EMPTY = TranslationDiff::Preview.new(sendable_sentences: 0, cached_sentences: 0, sendable_characters: 0).freeze

  # `provider:`, `config:` and `assume_supported:` are reserved, exactly as they are for Translator#initialize.
  def initialize(values, from: nil, to: nil, provider: nil, config: nil, assume_supported: false, **options)
    raise ArgumentError, "a preview needs a target language: pass `to:` a language code." if to.nil?

    @values = values
    @from = from
    @to = to
    @options = options
    @config = config || TranslationDiff.config
    @requested_provider = provider
    @assume_supported = assume_supported
  end

  def call
    segments = document_segments
    return EMPTY if segments.empty? || same_language?(@from)

    provider = resolve_provider
    from = resolve_source_language(provider)
    return EMPTY if same_language?(from)

    preview_for(provider, from, segments)
  end

  private

  def document_segments
    document = TranslationDiff::Document.new(TranslationDiff::Leaves.collapse_nils(@values))
    document.strings.flat_map { |string| passage(string).segments }.reject(&:empty?)
  end

  # opaque_elements comes from the configuration this call is actually using -- a context's own setting must
  # never fall back to Passage's global default.
  def passage(string)
    TranslationDiff::Passage.new(string, segmenter: @config.segmenter_instance, language: @from,
                                         opaque_elements: @config.opaque_elements)
  end

  # A detected language arrives as a String while `to:` is usually a Symbol, so neither type nor case can be assumed.
  def same_language?(from) = from.to_s.casecmp?(@to.to_s)

  # Same resolution Translator#call uses: a name to build, an object to use as it is, or the configured one.
  def resolve_provider = TranslationDiff::Providers.resolve(@requested_provider, @config)

  # `from:` given means the pair is already known, so it is validated once; `from:` nil needs a detection this
  # method never pays for, so it stops here instead of guessing what a paid request would have answered.
  def resolve_source_language(provider)
    return @from.tap { |from| ensure_supported!(provider, from) } unless @from.nil?

    ensure_supported!(provider, nil)
    raise_undetectable!(provider)
  end

  def raise_undetectable!(provider)
    unless provider.class.capabilities.detects_language?
      raise Error, "Provider #{provider.cache_key} cannot detect the source language. Pass `from:` with the " \
                   "source language code of the values you are previewing."
    end

    raise Error, "TranslationDiff.preview cannot detect the source language for #{provider.cache_key} " \
                 "without a paid request: pass `from:` explicitly."
  end

  # nil means we ship no data for this provider, and silence is not evidence of absence.
  def ensure_supported!(provider, from)
    return if @assume_supported || !@config.validate_languages

    supported = TranslationDiff::Languages.supports?(provider.cache_key, from: from, to: @to)
    return if supported.nil? || supported

    raise TranslationDiff::UnsupportedLanguageError,
          "Provider #{provider.cache_key} does not translate #{pair_description(from)}. If it does " \
          "now, pass `assume_supported: true` for this call, or set " \
          "`config.validate_languages = false`, and run `rake languages:refresh`."
  end

  def pair_description(from) = from.nil? ? "to #{@to}" : "#{from} to #{@to}"

  def preview_for(provider, from, segments)
    misses = fill(provider, from, segments)
    TranslationDiff::Preview.new(sendable_sentences: misses.size, cached_sentences: segments.size - misses.size,
                                 sendable_characters: misses.sum { |segment| segment.core.size })
  end

  # Reads the store through the same SentenceCache#fill translate uses; nothing here ever calls #store.
  def fill(provider, from, segments)
    cache = TranslationDiff::SentenceCache.new(store: @config.cache_store, provider: provider.cache_key,
                                               from: from, to: @to, options: @options)
    cache.fill(segments)
  end
end
