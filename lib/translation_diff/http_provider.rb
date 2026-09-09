# frozen_string_literal: true

require "faraday"
require "faraday/retry"
require "json"

# Every HTTP provider inherits this; no logging middleware, ever -- lines must carry no source text or credential.
class TranslationDiff::HTTPProvider < TranslationDiff::Provider
  RETRY_STATUSES = [429, 500, 502, 503, 504].freeze

  # Faraday raises these when nobody answered, as opposed to answering "no".
  TRANSPORT_FAILURES = [Faraday::ConnectionFailed, Faraday::TimeoutError, Faraday::SSLError].freeze

  def api_base = raise NotImplementedError, "#{self.class} must implement #api_base"
  def headers = {}

  def translate_url = raise NotImplementedError, "#{self.class} must implement #translate_url"

  def render_translate_payload(_request)
    raise NotImplementedError, "#{self.class} must implement #render_translate_payload"
  end

  def parse_translate_response(_body, _headers, _request)
    raise NotImplementedError, "#{self.class} must implement #parse_translate_response"
  end

  def translate(request)
    response = post(translate_url, render_translate_payload(request))
    parse_translate_response(response.body, response.headers, request)
  end

  def connection = @connection ||= build_connection

  private

  # Mirrors the shape a Faraday::Response would give if its own JSON middleware were still in the stack.
  Decoded = Data.define(:status, :headers, :body)
  private_constant :Decoded

  def post(url, payload)
    raw = connection.post(url, payload)
    response = Decoded.new(status: raw.status, headers: raw.headers, body: decode(raw))
    raise_for_status!(response)
    response
  rescue *TRANSPORT_FAILURES => e
    # The message is the transport's, never the payload's: the payload is the customer's text.
    raise TranslationDiff::TransportError, "#{self.class}: #{e.class}: #{e.message}"
  end

  # Faraday's JSON middleware passes parser options positionally, which json 3 (default on Ruby 4.x) removed.
  def decode(response)
    body = response.body
    return body unless body.is_a?(String)
    return body if body.strip.empty?
    return body unless json?(response)

    JSON.parse(body)
  rescue JSON::ParserError => e
    raise TranslationDiff::ResponseError,
          "#{self.class} returned a body that is not JSON: #{e.message[0, 200]}"
  end

  def json?(response) = response.headers["content-type"].to_s.match?(/\bjson\b/)

  # The block is how a test swaps in Faraday's test adapter; Amazon overrides it too, to sign the body as sent.
  def build_connection(&block)
    Faraday.new(url: api_base, headers: headers) do |faraday|
      faraday.request :json
      faraday.request :retry, retry_options
      adapt(faraday, &block)
      apply_timeouts(faraday)
    end
  end

  def adapt(faraday, &block)
    block ? block.call(faraday) : faraday.adapter(Faraday.default_adapter)
  end

  def apply_timeouts(faraday)
    faraday.options.open_timeout = config.open_timeout
    faraday.options.timeout = config.timeout
  end

  # faraday-retry reads Retry-After itself, which is why a 429 usually never reaches #raise_for_status!.
  def retry_options
    { max: config.max_retries, interval: 0.5, backoff_factor: 2, interval_randomness: 0.5,
      retry_statuses: RETRY_STATUSES, methods: %i[post get],
      exceptions: TRANSPORT_FAILURES + [Faraday::RetriableResponse] }
  end

  def raise_for_status!(response)
    status = response.status
    return if status < 400

    raise error_class(status).new(error_message(response), **error_options(response))
  end

  def error_class(status)
    case status
    when 401, 403 then TranslationDiff::AuthenticationError
    when 429 then TranslationDiff::RateLimitError
    when 456 then TranslationDiff::QuotaExceededError
    when 400..499 then TranslationDiff::InvalidRequestError
    else TranslationDiff::ServiceError
    end
  end

  def error_options(response)
    options = { provider: name, status: response.status }
    return options unless response.status == 429

    options.merge(retry_after: response.headers["Retry-After"]&.to_i)
  end

  # Truncated: an untruncated provider error body can be a whole HTML error page.
  def error_message(response)
    body = response.body
    text = body.is_a?(Hash) ? (body["message"] || body["error"] || body.to_s) : body.to_s
    "#{self.class} responded #{response.status}: #{text.to_s[0, 300]}"
  end
end
