# frozen_string_literal: true

# Declared, not discovered -- duck-typing left notranslate silently broken on two providers.
TranslationDiff::Capabilities = Data.define(:max_request_size, :max_batch_size,
                                            :max_text_size, :html, :notranslate,
                                            :detects_language, :reports_billing) do
  def html? = html != :none
  def notranslate? = notranslate
  def detects_language? = detects_language
  def reports_billing? = reports_billing
end
