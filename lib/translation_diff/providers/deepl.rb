# frozen_string_literal: true

# Talks to DeepL's REST API directly. This used to wrap deepl-rb; owning the
# request removed a dependency and, more to the point, removed a layer whose
# defaults were not ours -- deepl-rb logs the auth key and the payload at
# DEBUG, and its tag handling default silently disabled notranslate.
class TranslationDiff::Providers::DeepL < TranslationDiff::HTTPProvider
  PAID_HOST = "https://api.deepl.com"
  FREE_HOST = "https://api-free.deepl.com"

  # A key ending in :fx is a free-plan key, and the free plan lives on its
  # own host. DeepL's own libraries do this; so do we, now.
  FREE_KEY_SUFFIX = ":fx"

  # What arrives here is not plain text: the tokenizer hands over a
  # notranslate span with its tags. DeepL honours class="notranslate" only
  # under HTML tag handling; without it, in DeepL's words, "tags are treated
  # as regular text", and the protected content is translated while the tags
  # survive -- a failure nothing about the output reveals.
  DEFAULT_OPTIONS = { tag_handling: :html, tag_handling_version: "v2" }.freeze

  # 50 texts and a 128 KiB body are DeepL's documented per-request limits.
  # The request size stays at the 1700 escaped characters this library has
  # always used; the batch count is the number that was wrong (it said 300).
  def self.capabilities
    TranslationDiff::Capabilities.new(
      max_request_size: 1_700, max_batch_size: 50, max_text_size: nil,
      html: :tag_handling, notranslate: true, detects_language: true, reports_billing: true
    )
  end

  def self.configuration_options = %i[deepl_api_key deepl_api_base]
  def self.configuration_requirements = %i[deepl_api_key]

  # DeepL requires a target language even when only the detection is wanted,
  # so the provider picks one rather than making the caller do it.
  DETECTION_TARGET = "EN"

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

  # DeepL has no detection endpoint. Translating a sample and reading what it
  # says the source was is the only way, and is what this has always done.
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
