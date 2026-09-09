# frozen_string_literal: true

require "faraday"

# Builds a provider whose Faraday connection answers from a stub and records
# what was sent, so a test can assert on the payload as well as on the parse.
# Including this requires the test to define #config and #provider_class.
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
        recorder << env
        [status, { "Content-Type" => "application/json" }.merge(headers),
         body.is_a?(String) ? body : body.to_json]
      end
    end
  end

  def attach_stub(provider, stubs)
    provider.instance_variable_set(:@connection, provider.send(:build_connection) do |faraday|
      faraday.adapter :test, stubs
    end)
  end
end
