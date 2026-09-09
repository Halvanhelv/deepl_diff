# frozen_string_literal: true

# ModernMT. Adaptive translation with translation memories, which is
# thematically the closest of these services to what this library does.
class TranslationDiff::Providers::ModernMT < TranslationDiff::HTTPProvider
  HOST = "https://api.modernmt.com"

  # ModernMT spells its formats as MIME types.
  DEFAULT_FORMAT = "text/html"

  # Unverified. ModernMT documents an HTML format but says nothing about
  # class="notranslate", and no key was available to probe it. Declaring
  # false is the safe direction: a capability that under-promises costs a
  # warning, one that over-promises costs a customer's protected content.
  MODERNMT_HONOURS_NOTRANSLATE = false

  # 128 texts is documented. The per-request character limit is not, so the
  # conservative 5,000 Google recommends is used rather than a number nobody
  # published.
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
      .merge(q: request.texts, target: request.to.to_s)
      .tap { |payload| payload[:source] = request.from.to_s unless request.from.nil? }
  end

  # One text comes back as an object rather than a one-element array, so the
  # envelope is always coerced to a list before it is mapped.
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
    billed = results.filter_map { |r| r["billedCharacters"] }.sum

    TranslationDiff::Translation::Usage.new(
      characters: request.texts.sum(&:size),
      billed_characters: billed.positive? ? billed : nil
    )
  end
end

TranslationDiff::Providers.register(:modernmt, TranslationDiff::Providers::ModernMT)
