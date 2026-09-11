# One translation, coordinated: each step hands its value to the next, and a translation rides home on its own segment.
class TranslationDiff::Translator
  # Its own class, so rescuing a mis-driven translator cannot also swallow a provider or a cache failure.
  class Error < TranslationDiff::Error; end

  include TranslationDiff::Instrumentation

  attr_reader :config

  # `provider:`, `config:` and `assume_supported:` are reserved; every other keyword reaches the provider untouched.
  def initialize(values, from: nil, to: nil, provider: nil, config: nil, assume_supported: false, **options)
    raise ArgumentError, "a translation needs a target language: pass `to:` a language code." if to.nil?

    @values = values
    @from = from
    @to = to
    @options = options
    @config = config || TranslationDiff.config
    @requested_provider = provider
    @assume_supported = assume_supported
  end

  # Hands back the caller's value untouched unless something in it was actually translated.
  def call
    document = TranslationDiff::Document.new(TranslationDiff::Leaves.collapse_nils(@values))
    passages = document.strings.map { |string| passage(string) }
    segments = passages.flat_map(&:segments).reject(&:empty?)
    return @values if segments.empty?
    return @values if same_language?(@from)

    provider = resolve_provider
    from = resolve_source_language(provider, segments)
    return @values if same_language?(from)

    translated(document, passages, segments, provider, from)
  end

  private

  # `from:` given means the whole pair is already known, so it is validated once, up front. `from:` nil means
  # the target alone is checked before a possibly billed #detect runs, and the full pair only once it answers.
  def resolve_source_language(provider, segments)
    return @from.tap { |from| ensure_supported!(provider, from) } unless @from.nil?

    ensure_supported!(provider, nil)
    source_language(provider, segments).tap { |from| ensure_supported!(provider, from) }
  end

  # nil means we ship no data for this provider, and silence is not evidence of absence.
  # `from` nil (source not known yet) checks the target alone: a nil source is never itself refused.
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

  # The `translate` event wraps everything a call that reaches a provider does, and nothing an early return does.
  def translated(document, passages, segments, provider, from)
    values = TranslationDiff::Leaves.count(@values)
    characters = segments.sum { |segment| segment.core.size }
    payload = { call_id: call_id, from: from.to_s, to: @to.to_s, provider: provider.cache_key,
                values: values, characters: characters }
    instrument("translate", payload) do
      fill(provider, segments, from)
      rebuild(document, passages)
    end
  end

  # Opaque and short: a correlation key for this call's own events, generated once, never derived from the text.
  def call_id = @call_id ||= SecureRandom.hex(6)

  # Resolved at first use, never in the constructor: a value with nothing to translate needs no provider at all.
  def resolve_provider
    TranslationDiff::Providers.resolve(@requested_provider, config).tap { |provider| log("provider #{provider.class}") }
  end

  def passage(string)
    TranslationDiff::Passage.new(string, segmenter: config.segmenter_instance, language: @from)
  end

  # The strings walk and the map walk visit the same leaves in the same order, and the value itself was never touched.
  def rebuild(document, passages)
    rendered = passages.map(&:render)
    document.map { rendered.shift }
  end

  # Detection is attempted only where it is declared: every provider inherits a #detect that raises.
  def source_language(provider, segments)
    return @from unless @from.nil?

    ensure_detects_language!(provider)
    provider.detect(segments.first.core)
  end

  def ensure_detects_language!(provider)
    return if provider.class.capabilities.detects_language?

    raise Error, "Provider #{provider.cache_key} cannot detect the source language. Pass " \
                 "`from:` with the source language code of the values you are translating."
  end

  # A detected language arrives as a String while `to:` is usually a Symbol, so neither type nor case can be assumed.
  # A `from:` the caller gave settles this before a provider is resolved; a nil one cannot, and never matches.
  def same_language?(from) = from.to_s.casecmp?(@to.to_s)

  # The cache answers for what it has, the provider for the rest, and only what came back is written home.
  def fill(provider, segments, from)
    cache = TranslationDiff::SentenceCache.new(store: config.cache_store, provider: provider.cache_key,
                                               from: from, to: @to, options: @options)
    misses = cache.fill(segments)
    id = call_id
    instrument("cache", call_id: id, provider: provider.cache_key,
                        hits: segments.size - misses.size, misses: misses.size)
    TranslationDiff::Dispatcher.new(provider: provider, from: from, to: @to, options: @options,
                                    config: config, call_id: id).dispatch(misses)
    store(cache, misses, provider)
  end

  # A translation already paid for at the provider must reach the caller even if writing it back never does.
  def store(cache, misses, provider)
    cache.store(misses)
  rescue StandardError => e
    warn_log("cache write failed (#{e.class}), the translation is returned uncached")
    instrument("cache_error", call_id: call_id, provider: provider.cache_key, error: e.class.to_s)
  end
end
