# Answers what #translate would send and find cached, using the same segmenter, cache key and provider
# resolution translate uses -- without calling the provider or writing anything. Detection is a paid request
# this method never makes, so a nil `from:` for a provider that must detect the language is refused, not guessed at.
class TranslationDiff::Previewer
  # Its own class, so rescuing a preview that cannot be answered cannot also swallow a cache or provider failure.
  class Error < TranslationDiff::Error; end

  include TranslationDiff::CallPreparation

  EMPTY = TranslationDiff::Preview.new(sendable_sentences: 0, cached_sentences: 0, sendable_characters: 0,
                                       characters: 0).freeze

  attr_reader :config

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

  # Same resolution Translator#call uses: a name to build, an object to use as it is, or the configured one.
  def resolve_provider = TranslationDiff::Providers.resolve(@requested_provider, config)

  # `from:` given means the pair is already known, so it is validated once; `from:` nil needs a detection this
  # method never pays for, so it stops here instead of guessing what a paid request would have answered.
  def resolve_source_language(provider)
    return @from.tap { |from| ensure_supported!(provider, from) } unless @from.nil?

    ensure_supported!(provider, nil)
    raise_undetectable!(provider)
  end

  # A provider that cannot detect at all is refused with the same message translate uses; one that could but
  # would cost a paid request is refused too -- preview never spends money to answer what it would send.
  def raise_undetectable!(provider)
    ensure_detects_language!(provider, Error, "previewing")

    raise Error, "TranslationDiff.preview cannot detect the source language for #{provider.cache_key} " \
                 "without a paid request: pass `from:` explicitly."
  end

  # characters is the denominator: the same total the translate event itself reports, present even when every
  # segment is already cached and sendable_characters alone would leave nothing to divide by.
  def preview_for(provider, from, segments)
    misses = fill(provider, from, segments)
    TranslationDiff::Preview.new(sendable_sentences: misses.size, cached_sentences: segments.size - misses.size,
                                 sendable_characters: misses.sum { |segment| segment.core.size },
                                 characters: segments.sum { |segment| segment.core.size })
  end

  # Reads the store through the same SentenceCache#fill translate uses; nothing here ever calls #store.
  def fill(provider, from, segments) = cache_for(provider, from).fill(segments)
end
