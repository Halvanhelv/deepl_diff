# One translation, coordinated: each step hands its value to the next, and a translation rides home on its own segment.
class TranslationDiff::Translator
  # Its own class, so rescuing a mis-driven translator cannot also swallow a provider or a cache failure.
  class Error < TranslationDiff::Error; end

  include TranslationDiff::Instrumentation

  attr_reader :config

  # `provider:` and `config:` are reserved; every other keyword is forwarded to the provider untouched.
  def initialize(values, from: nil, to: nil, provider: nil, config: nil, **options)
    raise ArgumentError, "a translation needs a target language: pass `to:` a language code." if to.nil?

    @values = values
    @from = from
    @to = to
    @options = options
    @config = config || TranslationDiff.config
    @requested_provider = provider
  end

  # Hands back the caller's value untouched unless something in it was actually translated.
  def call
    document = TranslationDiff::Document.new(TranslationDiff::Leaves.collapse_nils(@values))
    passages = document.strings.map { |string| passage(string) }
    segments = passages.flat_map(&:segments).reject(&:empty?)
    return @values if segments.empty?

    provider = resolve_provider
    from = source_language(provider, segments)
    return @values if same_language?(from)

    translated(document, passages, segments, provider, from)
  end

  private

  # The `translate` event wraps everything a call that reaches a provider does, and nothing an early return does.
  def translated(document, passages, segments, provider, from)
    values = TranslationDiff::Leaves.count(@values)
    payload = { from: from.to_s, to: @to.to_s, provider: provider.cache_key, values: values }
    instrument("translate", payload) do
      fill(provider, segments, from)
      rebuild(document, passages)
    end
  end

  # Resolved at first use, never in the constructor: a value with nothing to translate needs no provider at all.
  def resolve_provider
    build_provider.tap do |provider|
      log("provider #{provider.class}")
      ensure_cache_key!(provider)
    end
  end

  # A provider arrives as a name to build, as an object to use as it is, or not at all -- then it is the configured one.
  def build_provider
    requested = @requested_provider
    return config.provider_instance if requested.nil?
    return TranslationDiff::Providers.build(requested, config) if requested.is_a?(Symbol) || requested.is_a?(String)

    TranslationDiff::Providers.ensure_provider!(requested)
  end

  # The cache key names the provider in every payload too: it is the one identifier every provider must have.
  def ensure_cache_key!(provider)
    return unless provider.cache_key.to_s.strip.empty?

    raise Error, "#{provider.class} must define #cache_key: a blank one would file its " \
                 "translations in every other provider's cache namespace."
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
  def same_language?(from) = from.to_s.casecmp?(@to.to_s)

  # The cache answers for what it has, the provider for the rest, and only what came back is written home.
  def fill(provider, segments, from)
    cache = sentence_cache(provider, from)
    misses = cache.fill(segments)
    instrument("cache", provider: provider.cache_key, hits: segments.size - misses.size, misses: misses.size)
    dispatch(provider, misses, from)
    cache.store(misses)
  end

  def sentence_cache(provider, from)
    TranslationDiff::SentenceCache.new(store: config.cache_store, provider: provider.cache_key,
                                       from: from, to: @to, options: @options)
  end

  def dispatch(provider, segments, from)
    batches = TranslationDiff::Batch.pack(segments, capabilities: provider.class.capabilities)
    batches.each { |batch| send_batch(provider, batch, from) }
  end

  # The batch applies the reply to the segments that produced it, so no step ever correlates by position again.
  def send_batch(provider, batch, from)
    texts = batch.texts
    payload = { provider: provider.cache_key, batch: texts.size, characters: texts.sum(&:size) }
    throttle(provider, payload[:characters])
    response = instrument("request", payload) { provider.translate(request(texts, from)) }
    batch.apply(response.texts)
  end

  def request(texts, from)
    TranslationDiff::Translation::Request.new(texts: texts, from: from, to: @to, options: @options)
  end

  # Consulted with what is about to be sent, before it is sent; nil means no rate limiting was configured at all.
  def throttle(provider, characters)
    limiter = config.rate_limiter_instance
    return if limiter.nil?

    instrument("rate_limit", provider: provider.cache_key, characters: characters) { limiter.check(characters) }
  end
end
