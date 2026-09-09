# frozen_string_literal: true

# LibreTranslate: open source, self-hosted, and the only provider here that
# can be run against for free, which is why it is worth supporting even
# though its translations are not the best of this set.
#
# It inverts the usual configuration: the base URL is required, because
# everyone runs their own instance, and the API key is optional, because most
# instances do not ask for one.
class TranslationDiff::Providers::LibreTranslate < TranslationDiff::HTTPProvider
  DEFAULT_FORMAT = "html"

  # The API's own way of asking for detection: `source` is required and
  # "auto" is the value that means "work it out".
  AUTO = "auto"

  # Observed, not assumed: probed 2026-09-09 against `docker run
  # libretranslate/libretranslate --load-only en,ru` (the argos-translate
  # en->ru model). `<span class="notranslate">Bold Mountain</span> is a good
  # place.` came back with the span tag intact but its content translated
  # anyway -- "Bold Mountain" became "Смелая гора". LibreTranslate's HTML
  # format preserves markup; it does not honour the notranslate marker.
  LIBRETRANSLATE_HONOURS_NOTRANSLATE = false

  # LibreTranslate publishes no per-request limits -- it is whatever the
  # instance operator configured. These are this library's own conservative
  # numbers, not the vendor's, and a self-hoster with a bigger instance can
  # raise them by subclassing.
  def self.capabilities
    TranslationDiff::Capabilities.new(
      max_request_size: 5_000, max_batch_size: 50, max_text_size: nil,
      html: :format, notranslate: LIBRETRANSLATE_HONOURS_NOTRANSLATE,
      detects_language: true, reports_billing: false
    )
  end

  def self.configuration_options = %i[libretranslate_api_key libretranslate_api_base]
  def self.configuration_requirements = %i[libretranslate_api_base]

  def api_base = config.libretranslate_api_base
  def translate_url = "translate"

  def render_translate_payload(request)
    { format: DEFAULT_FORMAT }
      .merge(request.options)
      .merge(q: request.texts, target: request.to.to_s,
             source: request.from.nil? ? AUTO : request.from.to_s)
      .tap { |payload| payload[:api_key] = config.libretranslate_api_key if config.libretranslate_api_key }
  end

  def parse_translate_response(body, _headers, request)
    translated = body["translatedText"]
    detected = body["detectedLanguage"]
    detected = detected.first if detected.is_a?(Array)

    TranslationDiff::Translation::Response.build(
      request: request,
      texts: translated.is_a?(Array) ? translated : [translated].compact,
      detected_source: detected.is_a?(Hash) ? detected["language"]&.downcase : nil,
      usage: TranslationDiff::Translation::Usage.new(characters: request.texts.sum(&:size))
    )
  end

  def detect(text)
    payload = { q: text }
    payload[:api_key] = config.libretranslate_api_key if config.libretranslate_api_key

    post("detect", payload).body.dig(0, "language")&.downcase
  end
end

TranslationDiff::Providers.register(:libretranslate, TranslationDiff::Providers::LibreTranslate)
