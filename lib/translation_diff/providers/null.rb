# Hands back what it was given -- for tests, and for wiring a pipeline up before a real provider is available.
class TranslationDiff::Providers::Null < TranslationDiff::Provider
  # Deliberately not detecting: this is the provider that proves the optional branch works.
  def self.capabilities
    TranslationDiff::Capabilities.new(
      max_request_size: 1_000_000, max_batch_size: 1_000_000, max_text_size: nil,
      html: :none, notranslate: false, detects_language: false, reports_billing: false
    )
  end

  def translate(request)
    TranslationDiff::Translation::Response.build(
      request: request, texts: request.texts.map(&:to_s)
    )
  end

  def cache_key = "null"
end

TranslationDiff::Providers.register(:null, TranslationDiff::Providers::Null)
