# frozen_string_literal: true

# What one provider can do and how much it will accept, declared rather than
# discovered. Before this existed, `max_batch_size` was a method, "can it
# detect a language" was `respond_to?(:detect)`, and "does it honour
# notranslate" was not expressed anywhere -- which is how two providers
# shipped with notranslate silently broken.
#
# `html` holds the name of the provider option that turns HTML handling on,
# because every vendor spells it differently (`tag_handling`, `format`,
# `textType`), or :none when the provider has no HTML mode at all.
TranslationDiff::Capabilities = Data.define(:max_request_size, :max_batch_size,
                                            :max_text_size, :html, :notranslate,
                                            :detects_language, :reports_billing) do
  def html? = html != :none
  def notranslate? = notranslate
  def detects_language? = detects_language
  def reports_billing? = reports_billing
end
