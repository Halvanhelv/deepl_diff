# frozen_string_literal: true

require "faraday"

# Builds a provider whose Faraday connection answers from a stub and records
# what was sent, so a test can assert on the payload as well as on the parse.
# Including this requires the test to define #config and #provider_class.
#
# `body:` is either a fixed response (a Hash, an Array, or a String) or a
# callable that is handed the request's Faraday env and returns one -- the
# latter is how a provider's own `provider` helper can echo back a response
# shaped to match however many texts a particular test happened to send,
# which the shared ProviderContract tests need and a fixed body cannot give
# them.
module StubbedProvider
  def requests = @requests ||= []

  def stub_provider(route:, body:, status: 200, headers: {}, name: :test)
    stubs = build_stubs(route: route, body: body, status: status, headers: headers)

    provider_class.new(config).tap do |built|
      built.name = name
      attach_stub(built, stubs)
    end
  end

  def sent = JSON.parse(requests.first.body)
  def query = CGI.parse(requests.first.url.query.to_s)

  private

  def build_stubs(route:, body:, status:, headers:)
    recorder = requests
    Faraday::Adapter::Test::Stubs.new do |stub|
      stub.post(route) do |env|
        # Faraday's test adapter reuses this env for the response, mutating
        # its body in place once the block returns -- capture a copy now or
        # every read after #translate returns sees the reply, not the
        # request.
        recorder << env.dup
        rendered = body.respond_to?(:call) ? body.call(env) : body
        [status, { "Content-Type" => "application/json" }.merge(headers),
         rendered.is_a?(String) ? rendered : rendered.to_json]
      end
    end
  end

  def attach_stub(provider, stubs)
    provider.instance_variable_set(:@connection, provider.send(:build_connection) do |faraday|
      faraday.adapter :test, stubs
    end)
  end
end
