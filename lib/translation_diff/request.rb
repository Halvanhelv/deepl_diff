# frozen_string_literal: true

class TranslationDiff::Request
  extend Forwardable
  include TranslationDiff::Instrumentation

  class Error < TranslationDiff::Error; end

  def_delegators :"TranslationDiff::Linearizer", :linearize, :restore

  def initialize(values, from: nil, to: nil, provider: nil, config: nil, **options)
    @values = values
    @from = from
    @to = to
    @provider = provider
    @config = config || TranslationDiff.config
    @options = options
  end

  def call
    return values if same_language? || nothing_to_translate?

    instrument("translate", from: from.to_s, to: to.to_s,
                            provider: provider_cache_key, values: texts.size) do
      translation
    end
  end

  private

  attr_reader :values, :options, :to, :config

  # The provider for this call: the `provider:` keyword when the caller gave
  # one, otherwise whatever the configuration resolves to.
  def api
    @api ||= (@provider.nil? ? config.provider_instance : resolve_provider(@provider))
             .tap { |provider| log("provider #{provider.class}") }
  end

  def resolve_provider(value)
    value.is_a?(Symbol) || value.is_a?(String) ? TranslationDiff::Providers.build(value, config) : value
  end

  def rate_limiter = config.rate_limiter_instance

  def from
    @from ||= detect_language
  end

  # A detected language arrives as a String while :to is usually a Symbol, so
  # the two have to be compared on equal footing or the short circuit never
  # fires and the text gets translated into its own language.
  def same_language?
    !to.nil? && from.to_s.casecmp?(to.to_s)
  end

  # Covers values holding no translatable text at all: "", nil, an empty
  # collection, or a scalar the tokenizer has nothing to say about.
  def nothing_to_translate?
    text_tokens_texts.all?(&:empty?)
  end

  def detect_language
    raise Error, "Pass from: -- #{api.class} cannot detect the source language" unless api.respond_to?(:detect)

    api.detect(text_tokens_texts.join(" ")[0..100])
  end

  # Extracts flat text array
  # => "Name", "<b>Good</b> boy"
  #
  # #values might be something like { name: "Name", bio: "<b>Good</b> boy" }
  def texts
    @texts ||= linearize(values)
  end

  # Converts each array item to token list
  # => [..., [["<b>", :markup], ["Good", :text], ...]]
  def tokens
    @tokens ||= texts.map do |value|
      TranslationDiff::Tokenizer.tokenize(value, segmenter: config.segmenter_instance, language: source_language)
    end
  end

  # The segmenter's language, not the resolved one: `from` triggers
  # auto-detection the first time it is called, and detection builds its
  # sample from the segmented text, so asking `from` here would be circular.
  # Only a language the caller actually passed is usable at this point --
  # everything else genuinely doesn't know yet, and nil is the honest
  # answer.
  def source_language
    @from&.to_s
  end

  # Extracts text tokens from token list
  # => { ..., "1_1" => "Good", 1_3 => "Boy", ... }
  def text_tokens
    @text_tokens ||= extract_text_tokens.to_h
  end

  def extract_text_tokens
    tokens.each_with_object([]).with_index do |(group, result), group_index|
      group.each_with_index do |(value, type), index|
        result << ["#{group_index}_#{index}", value] if type == :text
      end
    end
  end

  # Extracts values from text tokens
  # => [ ..., "Good", "Boy", ... ]
  def text_tokens_texts
    @text_tokens_texts ||= linearize(text_tokens).map(&:to_s).map(&:strip)
  end

  # Splits things requires translations to per-request chunks
  # (groups less 2k sym)
  # => [[ ..., "Good", "Boy", ... ]]
  def chunks
    @chunks ||= TranslationDiff::Chunker.new(
      text_tokens_texts,
      limit: api.max_request_size,
      count_limit: api.max_batch_size
    ).call
  end

  # Translates/loads from cache values from each chunk
  # => [[ ..., "Horoshiy", "Malchik", ... ]]
  def chunks_translated
    @chunks_translated ||= chunks.map do |chunk|
      cached, missing = cache.cached_and_missing(chunk)
      instrument("cache", provider: provider_cache_key,
                          hits: cached.count { |value| !value.nil? },
                          misses: missing.size)
      next cached if missing.empty?

      cache.store(chunk, cached, call_api(missing))
    end
  end

  # Restores indexes for translated tokens
  # => { ..., "1_1" => "Horoshiy", 1_3 => "Malchik", ... }
  def text_tokens_translated
    @text_tokens_translated ||=
      restore(text_tokens, chunks_translated.flatten)
  end

  # Restores tokens translated + adds same spacing as in source token
  # => [[..., [ "Horoshiy", :text ], ...]]
  # rubocop:disable-next Metrics/AbcSize
  def tokens_translated
    @tokens_translated ||= tokens.dup.tap do |tokens|
      text_tokens_translated.each do |index, value|
        group_index, index = index.split("_")
        tokens[group_index.to_i][index.to_i][0] =
          restore_spacing(tokens[group_index.to_i][index.to_i][0], value)
      end
    end
  end

  def restore_spacing(source_value, value)
    TranslationDiff::Spacing.restore(source_value, value)
  end

  # Restores texts from tokens
  # [..., "<b>Horoshiy</b> Malchik", ...]
  def texts_translated
    @texts_translated ||= tokens_translated.map.with_index do |group, index|
      source = texts[index]
      # Only strings are rebuilt from tokens. Anything else has no tokens to
      # rebuild from; nil keeps collapsing to "" the way it always has.
      next source unless source.nil? || source.is_a?(String)

      group.map { |value, type| type == :text ? value : fix_ascii(value) }.join
    end
  end

  # Final result
  def translation
    @translation ||= restore(values, texts_translated)
  end

  def call_api(values)
    check_rate_limit(values)
    translations = instrument("request", provider: provider_cache_key,
                                         batch: values.size,
                                         characters: values.sum(&:size)) do
      api.translate(values, from: from, to: to, **options)
    end
    return translations if translations.size == values.size

    # Letting a short response through means shifting nils into the results,
    # which surfaces much later as a NoMethodError far from the cause.
    raise Error,
          "Adapter returned #{translations.size} translations for #{values.size} values"
  end

  def cache
    @cache ||= TranslationDiff::Cache.new(
      from, to, provider: provider_cache_key, store: config.cache_store, options: options
    )
  end

  # A provider built through the registry is stamped with its name. An object
  # assigned straight to `config.provider` never passed through the registry,
  # so it has to supply this itself -- without it two providers' translations
  # would share cache entries and a caller would be served the wrong service's
  # answer.
  def provider_cache_key
    key = api.cache_key if api.respond_to?(:cache_key)
    return key unless key.nil? || key.to_s.strip.empty?

    raise Error,
          "#{api.class} must define #cache_key. A provider assigned directly rather " \
          "than registered by name has no name to fall back on, and without a key its " \
          "translations would share cache entries with every other provider."
  end

  def check_rate_limit(values)
    return if rate_limiter.nil?

    size = values.sum(&:size)
    instrument("rate_limit", provider: provider_cache_key, characters: size) do
      rate_limiter.check(size)
    end
  end

  # Markup should not contain control characters
  def fix_ascii(value)
    value.gsub(/[\u0000-\u001F]/, " ")
  end
end
