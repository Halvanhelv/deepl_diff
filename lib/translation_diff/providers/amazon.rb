# Amazon Translate: no batch API (one text per call), no HTML mode, and requests are signed, not just headed.
class TranslationDiff::Providers::Amazon < TranslationDiff::HTTPProvider
  SERVICE = "translate".freeze
  TARGET = "AWSShineFrontendService_20170701.TranslateText".freeze
  CONTENT_TYPE = "application/x-amz-json-1.1".freeze

  # Amazon's own way of asking for detection; reaches Comprehend under the hood, in regions that have it.
  AUTO = "auto".freeze

  def self.capabilities
    TranslationDiff::Capabilities.new(
      max_request_size: 10_000, max_batch_size: 1, max_text_size: 10_000,
      html: :none, notranslate: false, detects_language: true, reports_billing: false
    )
  end

  # Deliberately no environment fallback: this library does not implement the AWS credential chain.
  def self.configuration_options
    %i[amazon_access_key_id amazon_secret_access_key amazon_session_token
       amazon_region amazon_api_base]
  end

  def self.configuration_requirements
    %i[amazon_access_key_id amazon_secret_access_key amazon_region]
  end

  def api_base = config.amazon_api_base || "https://#{SERVICE}.#{config.amazon_region}.amazonaws.com"

  # Detected language is the first one Amazon reported: every text in a chunk shares a source language.
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
    # The message is the transport's, never the payload's: the payload is the customer's text.
    raise TranslationDiff::TransportError, "#{self.class}: #{e.class}: #{e.message}"
  end

  # Reuses the base's own decoding rather than a second, Faraday-middleware-based path (see HTTPProvider#decode).
  def decoded_response(raw) = Decoded.new(status: raw.status, headers: raw.headers, body: decode(raw))

  # Required here, not at load time, so an application using another provider never needs it installed.
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

  # The signature covers the body exactly as sent, so this omits `faraday.request :json` unlike the base class.
  def build_connection(&)
    Faraday.new(url: api_base, headers: headers) do |faraday|
      faraday.request :retry, retry_options
      adapt(faraday, &)
      apply_timeouts(faraday)
    end
  end
end

TranslationDiff::Providers.register(:amazon, TranslationDiff::Providers::Amazon)
