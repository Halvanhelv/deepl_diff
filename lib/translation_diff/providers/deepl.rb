# frozen_string_literal: true

# Talks to DeepL through deepl-rb's per-instance objects rather than its
# module-level shortcuts, so this library never calls DeepL.configure and
# never mutates another gem's global state. Two behaviours come for free by
# using their Configuration: it reads DEEPL_AUTH_KEY when no key is given,
# and it picks the free or the paid host from the key's ":fx" suffix.
#
# deepl-rb is not a dependency of this gem. It is required at build time, so
# an application using a different provider never needs it installed.
class TranslationDiff::Providers::DeepL
  # DeepL requires a target language even when only the detection is
  # wanted, so the provider picks one rather than making the caller do it.
  DETECTION_TARGET = "EN"

  MAX_REQUEST_SIZE = 1700
  MAX_BATCH_SIZE = 300

  # What arrives here is not plain text, despite having been through the
  # Tokenizer. A notranslate span is handed over whole, tags included --
  # that is how the tokenizer marks content the provider must leave alone.
  # DeepL honours `class="notranslate"` (and `translate="no"`) only under
  # HTML tag handling; without it, in DeepL's own words, "tags are treated
  # as regular text". The failure is quiet, because DeepL leaves the tags
  # themselves alone either way and only the protected content changes:
  #
  #   "<span class='notranslate'>Bold Mountain</span> is a good place."
  #   no tag_handling -> "<span class='notranslate'>Болд-Маунтин</span> — отличное место."
  #   tag_handling    -> "<span class='notranslate'>Bold Mountain</span> — это хорошее место."
  #
  # v2 is the tag handling algorithm DeepL's documentation recommends.
  # Note that under HTML tag handling DeepL defaults `split_sentences` to
  # `nonewlines`; this library sends one sentence at a time, so that
  # changes nothing here.
  DEFAULT_OPTIONS = { tag_handling: :html, tag_handling_version: "v2" }.freeze

  def self.configuration_options = %i[deepl_api_key deepl_host]

  # `config.logger` is deliberately NOT forwarded into DeepL::Configuration.
  # deepl-rb logs the whole request at DEBUG -- a "Request details:" line
  # carrying the Authorization header, DeepL auth key and all, followed by
  # the payload, which is the text being translated. This library's logger
  # carries a guarantee that no line it writes holds translated text, source
  # text, or a credential; handing it to a gem that logs payloads would break
  # that guarantee silently, at the exact moment someone turns DEBUG on to
  # diagnose a problem. Anyone who wants deepl-rb's own request log can build
  # the DeepL::API themselves, wrap it in this provider, and assign that to
  # `config.provider` -- see "Instrumentation and logging" in the README.
  def self.build(config)
    require "deepl"

    settings = { auth_key: config.deepl_api_key, host: config.deepl_host }.compact
    new(::DeepL::API.new(::DeepL::Configuration.new(settings)))
  rescue LoadError
    raise TranslationDiff::Error,
          "provider is :deepl but the `deepl-rb` gem is not available. " \
          'Add `gem "deepl-rb"` to your Gemfile.'
  end

  def initialize(api)
    @api = api
  end

  def translate(texts, from:, to:, **options)
    Array(request(texts, from, to, DEFAULT_OPTIONS.merge(options))).map(&:text)
  end

  def detect(text)
    request(text, nil, DETECTION_TARGET).detected_source_language.downcase
  end

  def max_request_size = MAX_REQUEST_SIZE
  def max_batch_size = MAX_BATCH_SIZE

  private

  def request(text, from, to, options = {})
    ::DeepL::Requests::Translate.new(@api, text, from, to, options).request
  end
end

TranslationDiff::Providers.register(:deepl, TranslationDiff::Providers::DeepL)
