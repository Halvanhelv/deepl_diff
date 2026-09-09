# frozen_string_literal: true

# Talks to Cloud Translation v2 (Basic) directly. This used to wrap
# google-cloud-translate-v2, which pulled googleauth, signet, os,
# google-protobuf and grpc in order to send one POST with a key in the query
# string.
class TranslationDiff::Providers::Google < TranslationDiff::HTTPProvider
  HOST = "https://translation.googleapis.com"

  # Google's own default, and what the tokenizer's output requires: a
  # notranslate span arrives with its tags, and entities such as &amp; stay
  # in the text. Asking for `text` makes Google translate the protected span
  # and drop its markup -- verified against the live API.
  DEFAULT_FORMAT = :html

  # Google's documented limits: 128 strings per request, and a recommended
  # 5,000 characters (the hard ceiling is 100 KB). Chunker measures the
  # URL-escaped form, never smaller than the UTF-8 byte count, so a chunk
  # inside 5,000 escaped characters is inside it in bytes too.
  def self.capabilities
    TranslationDiff::Capabilities.new(
      max_request_size: 5_000, max_batch_size: 128, max_text_size: nil,
      html: :format, notranslate: true, detects_language: true, reports_billing: false
    )
  end

  def self.configuration_options = %i[google_api_key google_project_id google_api_base]
  def self.configuration_requirements = %i[google_api_key]

  # A bare alphabetic code is downcased, so a configuration written for DeepL
  # ("EN") keeps working. Anything carrying a subtag ("zh-Hans", "pt-BR") is
  # passed through untouched: the casing of a script or region subtag is its
  # own, and a blanket downcase would corrupt it.
  BARE_LANGUAGE_CODE = /\A[A-Za-z]{2,3}\z/

  def api_base = config.google_api_base || HOST
  def translate_url = "language/translate/v2?key=#{CGI.escape(config.google_api_key.to_s)}"
  def detect_url = "language/translate/v2/detect?key=#{CGI.escape(config.google_api_key.to_s)}"

  def render_translate_payload(request)
    { format: DEFAULT_FORMAT }
      .merge(request.options)
      .merge(q: request.texts, target: language(request.to))
      .tap { |payload| payload[:source] = language(request.from) unless request.from.nil? }
  end

  def parse_translate_response(body, _headers, request)
    translations = Array(body.dig("data", "translations"))

    TranslationDiff::Translation::Response.build(
      request: request,
      texts: translations.map { |t| t["translatedText"] },
      detected_source: translations.first&.dig("detectedSourceLanguage")&.downcase,
      usage: TranslationDiff::Translation::Usage.new(characters: request.texts.sum(&:size))
    )
  end

  def detect(text)
    response = post(detect_url, { q: [text] })
    response.body.dig("data", "detections", 0, 0, "language")&.downcase
  end

  private

  def language(value)
    code = value.to_s
    return nil if code.empty?

    code.match?(BARE_LANGUAGE_CODE) ? code.downcase : code
  end
end

TranslationDiff::Providers.register(:google, TranslationDiff::Providers::Google)
