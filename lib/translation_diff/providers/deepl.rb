# Talks to DeepL's REST API directly, not deepl-rb: it logged the auth key at DEBUG and defaulted notranslate off.
class TranslationDiff::Providers::DeepL < TranslationDiff::HTTPProvider
  PAID_HOST = "https://api.deepl.com".freeze
  FREE_HOST = "https://api-free.deepl.com".freeze

  # A key ending in :fx is a free-plan key, and the free plan lives on its own host.
  FREE_KEY_SUFFIX = ":fx".freeze

  # DeepL honours class="notranslate" only under HTML tag handling -- otherwise content translates, tags survive.
  DEFAULT_OPTIONS = { tag_handling: :html, tag_handling_version: "v2" }.freeze

  # 50 texts / 128 KiB are DeepL's documented per-request limits; max_batch_size was wrong before (it said 300).
  def self.capabilities
    TranslationDiff::Capabilities.new(
      max_request_size: 1_700, max_batch_size: 50, max_text_size: nil,
      html: :tag_handling, notranslate: true, detects_language: true, reports_billing: true
    )
  end

  def self.configuration_options = %i[deepl_api_key deepl_api_base]
  def self.configuration_requirements = %i[deepl_api_key]

  # DeepL requires a target language even when only detection is wanted, so the provider picks one.
  DETECTION_TARGET = "EN".freeze

  def api_base
    config.deepl_api_base || (free_key? ? FREE_HOST : PAID_HOST)
  end

  def headers = { "Authorization" => "DeepL-Auth-Key #{config.deepl_api_key}" }

  def translate_url = "v2/translate"

  def render_translate_payload(request)
    DEFAULT_OPTIONS
      .merge(request.options)
      .merge(text: request.texts, target_lang: language(request.to))
      .tap { |payload| payload[:source_lang] = language(request.from) unless request.from.nil? }
  end

  def parse_translate_response(body, _headers, request)
    translations = Array(body["translations"])

    TranslationDiff::Translation::Response.build(
      request: request,
      texts: translations.map { |t| t["text"] },
      detected_source: translations.first&.dig("detected_source_language")&.downcase,
      usage: usage_for(request, translations)
    )
  end

  # DeepL has no detection endpoint; translating a sample and reading the source it reports is the only way.
  def detect(text)
    request = TranslationDiff::Translation::Request.new(texts: [text], from: nil,
                                                        to: DETECTION_TARGET)
    translate(request).detected_source
  end

  private

  def free_key? = config.deepl_api_key.to_s.end_with?(FREE_KEY_SUFFIX)

  # DeepL's language codes are upper case.
  def language(value) = value.to_s.upcase

  def usage_for(request, translations)
    billed = translations.filter_map { |t| t["billed_characters"] }.sum

    TranslationDiff::Translation::Usage.new(
      characters: request.texts.sum(&:size),
      billed_characters: billed.positive? ? billed : nil
    )
  end
end

TranslationDiff::Providers.register(:deepl, TranslationDiff::Providers::DeepL)
