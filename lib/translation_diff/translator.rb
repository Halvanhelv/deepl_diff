# One translation, coordinated: each step hands its value to the next, and a translation rides home on its own segment.
class TranslationDiff::Translator
  # Its own class, so rescuing a mis-driven translator cannot also swallow a provider or a cache failure.
  class Error < TranslationDiff::Error; end

  include TranslationDiff::Instrumentation

  attr_reader :config

  # `provider:` and `config:` are reserved; every other keyword is forwarded to the provider untouched.
  def initialize(values, from: nil, to: nil, provider: nil, config: nil, **options)
    @values = values
    @from = from
    @to = to
    @options = options
    @config = config || TranslationDiff.config
    @provider = resolve(provider)
    @name = provider_name(@provider)
    log("provider #{@provider.class}")
  end

  # Hands back the caller's value untouched unless something in it was actually translated.
  def call
    document = TranslationDiff::Document.new(@values)
    passages = document.strings.map { |string| passage(string) }
    segments = passages.flat_map(&:segments).reject(&:empty?)
    return @values if segments.empty?

    from = source_language(segments)
    return @values if same_language?(from)

    instrument("translate", from: from, to: @to, provider: @name, values: passages.size) do
      fill(segments, from)
      rebuild(document, passages)
    end
  end

  private

  # A provider arrives as a name to build, as an object to use as it is, or not at all -- then it is the configured one.
  def resolve(provider)
    return config.provider_instance if provider.nil?
    return TranslationDiff::Providers.build(provider, config) if provider.is_a?(Symbol) || provider.is_a?(String)

    TranslationDiff::Providers.ensure_provider!(provider)
  end

  # The cache key names the provider in every payload too: it is the one identifier every provider must have.
  def provider_name(provider)
    key = provider.cache_key.to_s
    return key unless key.strip.empty?

    raise Error,
          "#{provider.class} must define #cache_key: a blank one would file its translations " \
          "in every other provider's cache namespace."
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
  def source_language(segments)
    return @from unless @from.nil?

    ensure_detects_language!
    @provider.detect(segments.first.core)
  end

  def ensure_detects_language!
    return if @provider.class.capabilities.detects_language?

    raise Error,
          "Provider #{@name} cannot detect the source language. Pass `from:` with the " \
          "source language code of the values you are translating."
  end

  # A detected language arrives as a String while `to:` is usually a Symbol, so neither type nor case can be assumed.
  def same_language?(from) = from.to_s.casecmp?(@to.to_s)

  # The cache answers for what it has, the provider for the rest, and only what came back is written home.
  def fill(segments, from)
    cache = sentence_cache(from)
    misses = cache.fill(segments)
    instrument("cache", provider: @name, hits: segments.size - misses.size, misses: misses.size)
    dispatch(misses, from)
    cache.store(misses)
  end

  def sentence_cache(from)
    TranslationDiff::SentenceCache.new(store: config.cache_store, provider: @name,
                                       from: from, to: @to, options: @options)
  end

  def dispatch(segments, from)
    capabilities = @provider.class.capabilities
    TranslationDiff::Batch.pack(segments, capabilities: capabilities).each { |batch| send_batch(batch, from) }
  end

  # The batch applies the reply to the segments that produced it, so no step ever correlates by position again.
  def send_batch(batch, from)
    texts = batch.texts
    characters = texts.sum(&:size)
    throttle(characters)
    response = instrument("request", provider: @name, batch: texts.size, characters: characters) do
      @provider.translate(request(texts, from))
    end
    batch.apply(response.texts)
  end

  def request(texts, from)
    TranslationDiff::Translation::Request.new(texts: texts, from: from, to: @to, options: @options)
  end

  # Consulted with what is about to be sent, before it is sent; nil means no rate limiting was configured at all.
  def throttle(characters)
    limiter = config.rate_limiter_instance
    return if limiter.nil?

    instrument("rate_limit", provider: @name, characters: characters) { limiter.check(characters) }
  end
end
