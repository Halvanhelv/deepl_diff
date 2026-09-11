# Sends batches to the provider, throttles each one, and reports what it cost -- the seam between cache and wire.
class TranslationDiff::Dispatcher
  include TranslationDiff::Instrumentation

  attr_reader :config

  def initialize(provider:, from:, to:, call_id:, options: {}, config: nil)
    @provider = provider
    @from = from
    @to = to
    @call_id = call_id
    @options = options
    @config = config || TranslationDiff.config
  end

  def dispatch(segments)
    batches = TranslationDiff::Batch.pack(segments, capabilities: @provider.class.capabilities)
    batches.each { |batch| send_batch(batch) }
  end

  private

  # The batch applies the reply to the segments that produced it, so no step ever correlates by position again.
  def send_batch(batch)
    texts = batch.texts
    payload = { call_id: @call_id, provider: @provider.cache_key, batch: texts.size, characters: texts.sum(&:size) }
    throttle(payload[:characters])
    response = instrument("request", payload) { @provider.translate(request(texts)) }
    report_usage(response, payload[:characters])
    batch.apply(response.texts)
  end

  def request(texts)
    TranslationDiff::Translation::Request.new(texts: texts, from: @from, to: @to, options: @options)
  end

  # Consulted with what is about to be sent, before it is sent; nil means no rate limiting was configured at all.
  def throttle(characters)
    limiter = config.rate_limiter_instance
    return if limiter.nil?

    instrument("rate_limit", call_id: @call_id, provider: @provider.cache_key,
                             characters: characters) { limiter.check(characters) }
  end

  # A point event: what this request cost, as this library counted it -- a provider's own count never overrides it.
  def report_usage(response, characters)
    usage = response.usage

    instrument("usage", call_id: @call_id,
                        provider: @provider.cache_key,
                        characters: characters,
                        billed_characters: usage&.billed_characters,
                        reported: @provider.class.capabilities.reports_billing?,
                        model: usage&.model)
  end
end
