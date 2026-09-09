require "faraday"

# Builds a provider whose Faraday connection answers from a stub and records what was sent.
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
        # Faraday's test adapter mutates this env's body in place for the response -- dup it now, or lose the request.
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
