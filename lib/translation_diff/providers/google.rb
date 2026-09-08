# frozen_string_literal: true

# Talks to Google Cloud Translation v2 (Basic) through the API object the
# google-cloud-translate-v2 gem builds, rather than its module-level
# shortcuts, so this library never mutates another gem's global state. Two
# behaviours come for free by using their constructor: it reads TRANSLATE_KEY
# and GOOGLE_CLOUD_KEY when no key is given, and it falls back to application
# default credentials when there is no key at all.
#
# google-cloud-translate-v2 is not a dependency of this gem. It is required
# at build time, so an application using a different provider never needs it
# installed.
class TranslationDiff::Providers::Google
  # Google's own numbers. The batch limit is a hard one -- "the maximum
  # number of strings is 128" -- and a larger request is rejected outright.
  # The size limit is the documented recommendation of 5K characters per
  # request, well under the hard 100K-byte ceiling. Chunker measures the
  # URL-escaped form, which is never smaller than the UTF-8 byte count, so
  # staying under this in escaped characters keeps every request under it in
  # bytes too.
  MAX_REQUEST_SIZE = 5_000
  MAX_BATCH_SIZE = 128

  # What arrives here is not plain text, despite having been through the
  # Tokenizer. A notranslate span is handed over whole, tags included --
  # that is how the tokenizer marks content the provider must leave alone --
  # and HTML entities such as `&amp;` stay in the text it emits. Asking
  # Google for `text` makes it translate the protected span and drop the
  # markup around it entirely:
  #
  #   "<span class='notranslate'>Bold Mountain</span> is a good place."
  #   format: text  -> "Болд Маунтин — хорошее место."
  #   format: html  -> "<span class='notranslate'>Bold Mountain</span> — хорошее место."
  #
  # So `html` it is, which is also what this gem sent for its whole life
  # before the provider seam existed. The cost is that Google escapes its
  # own output -- a literal apostrophe returns as "&#39;" -- which is
  # correct inside the HTML fragment these values usually are, and noise
  # inside a value that never had markup in it. A caller translating bare
  # strings can pass `format: :text` per call.
  DEFAULT_FORMAT = :html

  # A bare alphabetic code is downcased, so a configuration written for
  # DeepL ("EN") keeps working against Google, whose codes are lowercase.
  # Anything else is passed through untouched: "zh-Hans", "zh-CN" and
  # "pt-BR" carry script and region subtags whose casing is their own, and a
  # blanket downcase would corrupt them.
  BARE_LANGUAGE_CODE = /\A[A-Za-z]{2,3}\z/

  def self.configuration_options = %i[google_api_key google_project_id]

  # `config.logger` is deliberately not forwarded: the gem takes no logger,
  # and this library's own guarantee -- that no line it writes holds source
  # text, translated text or a credential -- is easiest to keep by never
  # handing the logger to a gem that has not made the same promise.
  def self.build(config)
    require "google/cloud/translate/v2"

    settings = { key: config.google_api_key, project_id: config.google_project_id }.compact
    new(::Google::Cloud::Translate::V2.new(**settings))
  rescue LoadError
    raise TranslationDiff::Error,
          "provider is :google but the `google-cloud-translate-v2` gem is not available. " \
          'Add `gem "google-cloud-translate-v2"` to your Gemfile.'
  end

  def initialize(api)
    @api = api
  end

  def translate(texts, from:, to:, **options)
    settings = { from: language(from), to: language(to), format: DEFAULT_FORMAT }.merge(options)

    results = @api.translate(*texts, **settings)
    # One text yields a bare Translation, not a one-element array. `Array()`
    # is not usable to even that out: Translation would have to be trusted
    # never to define #to_a or #to_ary, and if it ever did, `Array()` would
    # quietly splat one translation into several strings instead of raising.
    results = [results] unless results.is_a?(Array)

    results.map(&:text)
  end

  def detect(text)
    @api.detect(text).language
  end

  def max_request_size = MAX_REQUEST_SIZE
  def max_batch_size = MAX_BATCH_SIZE

  private

  def language(value)
    code = value.to_s
    return nil if code.empty?

    code.match?(BARE_LANGUAGE_CODE) ? code.downcase : code
  end
end

TranslationDiff::Providers.register(:google, TranslationDiff::Providers::Google)
