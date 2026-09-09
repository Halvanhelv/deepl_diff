# frozen_string_literal: true

# Azure AI Translator, REST v3.0: cheapest per character, most generous per request (1,000 strings/50,000 chars).
class TranslationDiff::Providers::Azure < TranslationDiff::HTTPProvider
  HOST = "https://api.cognitive.microsofttranslator.com"
  API_VERSION = "3.0"

  # Azure spells HTML handling `textType`, and under it honours `class=notranslate` like DeepL and Google do.
  DEFAULT_TEXT_TYPE = "html"

  def self.capabilities
    TranslationDiff::Capabilities.new(
      max_request_size: 50_000, max_batch_size: 1_000, max_text_size: 50_000,
      html: :textType, notranslate: true, detects_language: true, reports_billing: true
    )
  end

  def self.configuration_options = %i[azure_api_key azure_region azure_api_base]
  def self.configuration_requirements = %i[azure_api_key]

  def api_base = config.azure_api_base || HOST

  # A multi-service resource needs the region header; a single-service one rejects nothing without it.
  def headers
    { "Ocp-Apim-Subscription-Key" => config.azure_api_key.to_s }
      .tap { |h| h["Ocp-Apim-Subscription-Region"] = config.azure_region if config.azure_region }
  end

  # Azure takes the language pair in the query string, so the URL is built per request, not a constant.
  def translate_url = "translate"

  def translate(request)
    response = post(url_for(request), render_translate_payload(request))
    parse_translate_response(response.body, response.headers, request)
  end

  def render_translate_payload(request) = request.texts.map { |text| { Text: text } }

  def parse_translate_response(body, headers, request)
    results = Array(body)

    TranslationDiff::Translation::Response.build(
      request: request,
      texts: results.map { |result| result.dig("translations", 0, "text") },
      detected_source: results.first&.dig("detectedLanguage", "language")&.downcase,
      usage: TranslationDiff::Translation::Usage.new(
        characters: request.texts.sum(&:size),
        billed_characters: headers["x-metered-usage"]&.to_i
      )
    )
  end

  def detect(text)
    response = post("detect?api-version=#{API_VERSION}", [{ Text: text }])
    response.body.dig(0, "language")&.downcase
  end

  private

  def url_for(request)
    params = { "api-version" => API_VERSION, "to" => request.to.to_s,
               "textType" => DEFAULT_TEXT_TYPE }
    params["from"] = request.from.to_s unless request.from.nil?
    params.merge!(request.options.transform_keys(&:to_s))

    "#{translate_url}?#{URI.encode_www_form(params)}"
  end
end

TranslationDiff::Providers.register(:azure, TranslationDiff::Providers::Azure)
