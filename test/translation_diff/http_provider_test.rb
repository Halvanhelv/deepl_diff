# frozen_string_literal: true

require "test_helper"
require "faraday"

class HTTPProviderTest < Minitest::Test
  # A provider that exists only to exercise the base class.
  class Echo < TranslationDiff::HTTPProvider
    def api_base = "https://echo.test"
    def headers = { "X-Echo" => "1" }
    def translate_url = "v1/translate"
    def render_translate_payload(request) = { "q" => request.texts }

    def parse_translate_response(body, _headers, request)
      TranslationDiff::Translation::Response.build(request: request, texts: body["translations"])
    end
  end

  def setup
    @config = TranslationDiff::Configuration.new
  end

  def request(texts = %w[one])
    TranslationDiff::Translation::Request.new(texts: texts, from: "en", to: "ru")
  end

  # Faraday's test adapter: no webmock, no network, same middleware stack the real connection has.
  def provider_for(status:, body:, headers: {})
    stubs = Faraday::Adapter::Test::Stubs.new do |stub|
      stub.post("/v1/translate") { [status, headers, body] }
    end
    Echo.new(@config).tap do |provider|
      provider.instance_variable_set(:@connection, provider.send(:build_connection) do |faraday|
        faraday.adapter :test, stubs
      end)
    end
  end

  def test_it_posts_the_rendered_payload_and_parses_the_reply
    provider = provider_for(status: 200, body: { "translations" => %w[один] }.to_json,
                            headers: { "Content-Type" => "application/json" })

    assert_equal %w[один], provider.translate(request).texts
  end

  def test_a_401_becomes_an_authentication_error_naming_the_provider
    provider = provider_for(status: 401, body: "nope")
    provider.name = :echo

    error = assert_raises(TranslationDiff::AuthenticationError) { provider.translate(request) }

    assert_equal :echo, error.provider
    assert_equal 401, error.status
  end

  def test_a_400_becomes_an_invalid_request_error
    provider = provider_for(status: 400, body: "bad")

    assert_raises(TranslationDiff::InvalidRequestError) { provider.translate(request) }
  end

  def test_a_456_becomes_a_quota_error
    provider = provider_for(status: 456, body: "out of quota")

    assert_raises(TranslationDiff::QuotaExceededError) { provider.translate(request) }
  end

  def test_a_500_becomes_a_service_error
    provider = provider_for(status: 500, body: "boom")

    assert_raises(TranslationDiff::ServiceError) { provider.translate(request) }
  end

  # Retries are turned off; what is asserted here is the mapping, not the retrying.
  def test_a_429_becomes_a_rate_limit_error_carrying_retry_after
    @config.max_retries = 0
    provider = provider_for(status: 429, body: "slow down", headers: { "Retry-After" => "17" })

    error = assert_raises(TranslationDiff::RateLimitError) { provider.translate(request) }

    assert_equal 17, error.retry_after
  end

  def test_a_connection_failure_becomes_a_transport_error
    @config.max_retries = 0
    stubs = Faraday::Adapter::Test::Stubs.new do |stub|
      stub.post("/v1/translate") { raise Faraday::ConnectionFailed, "no route" }
    end
    provider = Echo.new(@config)
    provider.instance_variable_set(:@connection, provider.send(:build_connection) do |faraday|
      faraday.adapter :test, stubs
    end)

    assert_raises(TranslationDiff::TransportError) { provider.translate(request) }
  end

  # No line this library writes may carry source text or a credential.
  def test_no_logging_middleware_is_installed_even_when_a_logger_is_configured
    @config.logger = Logger.new(StringIO.new)
    handlers = Echo.new(@config).connection.builder.handlers

    refute_includes handlers.map(&:name), "Faraday::Response::Logger"
  end

  def test_the_configured_timeouts_reach_the_connection
    @config.open_timeout = 2
    @config.timeout = 7
    connection = Echo.new(@config).connection

    assert_equal 2, connection.options.open_timeout
    assert_equal 7, connection.options.timeout
  end

  def test_the_subclass_headers_are_sent
    connection = Echo.new(@config).connection

    assert_equal "1", connection.headers["X-Echo"]
  end

  def test_it_decodes_a_json_body_without_faradays_middleware
    provider = provider_for(status: 200, body: { "translations" => %w[один] }.to_json,
                            headers: { "Content-Type" => "application/json" })

    assert_equal %w[один], provider.translate(request).texts
  end

  # An error page from a proxy is HTML, and the error path must survive it.
  def test_a_non_json_error_body_still_produces_the_mapped_error
    provider = provider_for(status: 500, body: "<html>gateway</html>",
                            headers: { "Content-Type" => "text/html" })

    error = assert_raises(TranslationDiff::ServiceError) { provider.translate(request) }

    assert_match(/gateway/, error.message)
  end
end
