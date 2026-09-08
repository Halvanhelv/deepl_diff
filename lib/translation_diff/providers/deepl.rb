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

  def self.configuration_options = %i[deepl_api_key deepl_host]

  def self.build(config)
    require "deepl"

    settings = { auth_key: config.deepl_api_key,
                 host: config.deepl_host,
                 logger: config.logger }.compact
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
    Array(request(texts, from, to, options)).map(&:text)
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
