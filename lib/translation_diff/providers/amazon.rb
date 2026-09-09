# frozen_string_literal: true

# Amazon Translate. The odd one out of this set in three ways, all of which
# the capabilities declare rather than hide:
#
# - It translates one text per call. There is no batch form of TranslateText,
#   so a hundred sentences are a hundred requests. `max_batch_size: 1` makes
#   Chunker produce one text per chunk, which is correct and slow.
# - It has no HTML mode, so a notranslate span sent to it is translated like
#   any other text. `notranslate: false` is what lets the rest of the library
#   warn instead of discovering it in production.
# - Its requests are signed rather than merely headed, which is why this
#   class overrides #translate instead of filling in the usual seams, and
#   why it overrides #build_connection to drop the JSON request middleware:
#   the signature covers the body exactly as sent, so nothing may re-encode
#   it afterwards.
class TranslationDiff::Providers::Amazon < TranslationDiff::HTTPProvider
  SERVICE = "translate"
  TARGET = "AWSShineFrontendService_20170701.TranslateText"
  CONTENT_TYPE = "application/x-amz-json-1.1"

  # Amazon's own way of asking for detection. It reaches Amazon Comprehend
  # under the hood and is only available in regions that have it.
  AUTO = "auto"

  def self.capabilities
    TranslationDiff::Capabilities.new(
      max_request_size: 10_000, max_batch_size: 1, max_text_size: 10_000,
      html: :none, notranslate: false, detects_language: true, reports_billing: false
    )
  end

  def self.configuration_options
    %i[amazon_access_key_id amazon_secret_access_key amazon_session_token
       amazon_region amazon_api_base]
  end

  def self.configuration_requirements
    %i[amazon_access_key_id amazon_secret_access_key amazon_region]
  end

  def api_base = config.amazon_api_base || "https://#{SERVICE}.#{config.amazon_region}.amazonaws.com"

  # One request per text, in order. The response's detected language is the
  # first one Amazon reported: every text in a chunk comes from the same
  # document, so they share a source language.
  def translate(request)
    detected = nil
    texts = request.texts.map do |text|
      body = call(text, request)
      detected ||= body["SourceLanguageCode"]&.downcase
      body["TranslatedText"]
    end

    TranslationDiff::Translation::Response.build(
      request: request, texts: texts, detected_source: detected,
      usage: TranslationDiff::Translation::Usage.new(characters: request.texts.sum(&:size))
    )
  end

  def detect(text)
    call(text, TranslationDiff::Translation::Request.new(texts: [text], from: nil, to: "en"))
      .fetch("SourceLanguageCode", nil)&.downcase
  end

  private

  def call(text, request)
    payload = {
      "Text" => text,
      "SourceLanguageCode" => request.from.nil? ? AUTO : request.from.to_s,
      "TargetLanguageCode" => request.to.to_s
    }.merge(request.options.transform_keys(&:to_s))

    post_signed(JSON.generate(payload)).body
  end

  def post_signed(body)
    raw = connection.post("/", body, signed_headers(body))
    response = decoded_response(raw)
    raise_for_status!(response)
    response
  rescue *TRANSPORT_FAILURES => e
    # The message is the transport's, never the payload's: the payload is the
    # customer's text.
    raise TranslationDiff::TransportError, "#{self.class}: #{e.class}: #{e.message}"
  end

  # Reuses the base's own decoding (`decode`, `Decoded`, `json?`) rather than
  # a second, Faraday-middleware-based path: that middleware is exactly what
  # HTTPProvider's own #post avoids, since it breaks under the `json` 3 gem
  # that ships by default on Ruby 4.x.
  def decoded_response(raw) = Decoded.new(status: raw.status, headers: raw.headers, body: decode(raw))

  # aws-sigv4 is Amazon's own signing library and nothing more: no clients, no
  # service models, one dependency. It is required here rather than at load
  # time so an application using another provider never needs it installed.
  def signer
    @signer ||= begin
      require_sigv4
      Aws::Sigv4::Signer.new(
        service: SERVICE, region: config.amazon_region,
        access_key_id: config.amazon_access_key_id,
        secret_access_key: config.amazon_secret_access_key,
        session_token: config.amazon_session_token
      )
    end
  end

  def require_sigv4
    require "aws-sigv4"
  rescue LoadError
    raise TranslationDiff::Error,
          "provider is :amazon but the `aws-sigv4` gem is not available. " \
          'Add `gem "aws-sigv4"` to your Gemfile.'
  end

  def signed_headers(body)
    signature = signer.sign_request(
      http_method: "POST", url: "#{api_base}/", body: body,
      headers: { "Content-Type" => CONTENT_TYPE, "X-Amz-Target" => TARGET }
    )

    signature.headers.merge("Content-Type" => CONTENT_TYPE, "X-Amz-Target" => TARGET)
  end

  # The signature covers the body exactly as sent, so this connection must
  # not have a JSON request middleware re-encoding it afterwards -- unlike
  # the base class's #build_connection, this one omits `faraday.request
  # :json`.
  def build_connection(&block)
    Faraday.new(url: api_base, headers: headers) do |faraday|
      faraday.request :retry, retry_options
      adapt(faraday, &block)
      apply_timeouts(faraday)
    end
  end
end

TranslationDiff::Providers.register(:amazon, TranslationDiff::Providers::Amazon)
