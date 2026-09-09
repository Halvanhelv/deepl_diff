# ModernMT: adaptive translation with translation memories.
class TranslationDiff::Providers::ModernMT < TranslationDiff::HTTPProvider
  HOST = "https://api.modernmt.com".freeze

  # ModernMT spells its formats as MIME types.
  DEFAULT_FORMAT = "text/html".freeze

  # Unverified, not observed: no key was available to probe it; false is the safe assumption either way.
  MODERNMT_HONOURS_NOTRANSLATE = false

  # 128 texts is documented; the character limit is not, so Google's 5,000 recommendation is borrowed.
  def self.capabilities
    TranslationDiff::Capabilities.new(
      max_request_size: 5_000, max_batch_size: 128, max_text_size: nil,
      html: :format, notranslate: MODERNMT_HONOURS_NOTRANSLATE,
      detects_language: true, reports_billing: true
    )
  end

  def self.configuration_options = %i[modernmt_api_key modernmt_api_base]
  def self.configuration_requirements = %i[modernmt_api_key]

  def api_base = config.modernmt_api_base || HOST
  def headers = { "MMT-ApiKey" => config.modernmt_api_key.to_s }
  def translate_url = "translate"

  def render_translate_payload(request)
    { format: DEFAULT_FORMAT }
      .merge(request.options)
      .merge(q: request.texts, target: language(request.to))
      .tap { |payload| payload[:source] = language(request.from) unless request.from.nil? }
  end

  # One text comes back as an object rather than a one-element array, so the envelope is always coerced.
  def parse_translate_response(body, _headers, request)
    results = results_from(body)

    TranslationDiff::Translation::Response.build(
      request: request,
      texts: results.map { |r| r["translation"] },
      detected_source: results.first&.dig("detectedLanguage")&.downcase,
      usage: usage_for(request, results)
    )
  end

  def detect(text)
    request = TranslationDiff::Translation::Request.new(texts: [text], from: nil, to: "en")
    translate(request).detected_source
  end

  private

  def results_from(body)
    data = body["data"]
    data.is_a?(Array) ? data : [data].compact
  end

  def usage_for(request, results)
    TranslationDiff::Translation::Usage.new(
      characters: request.texts.sum(&:size),
      billed_characters: billed_characters(results.map { |r| r["billedCharacters"] })
    )
  end
end

TranslationDiff::Providers.register(:modernmt, TranslationDiff::Providers::ModernMT)
