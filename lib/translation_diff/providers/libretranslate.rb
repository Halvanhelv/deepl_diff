# The only free, self-hosted provider here; base URL is required (everyone runs their own), API key is optional.
class TranslationDiff::Providers::LibreTranslate < TranslationDiff::HTTPProvider
  DEFAULT_FORMAT = "html".freeze

  # The API's own way of asking for detection: `source` is required, and "auto" means "work it out".
  AUTO = "auto".freeze

  # Observed 2026-09-09 via Docker: LibreTranslate's HTML format preserves markup but translates content anyway.
  LIBRETRANSLATE_HONOURS_NOTRANSLATE = false

  # LibreTranslate publishes no per-request limits; these are this library's own conservative numbers.
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
