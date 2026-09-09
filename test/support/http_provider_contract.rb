# What every HTTP-backed provider must do; including this requires the test to define #provider and #config.
module HTTPProviderContract
  def test_it_declares_an_api_base_that_is_a_url
    assert_match(%r{\Ahttps?://}, provider.api_base)
  end

  def test_it_installs_no_logging_middleware
    config.logger = Logger.new(StringIO.new)
    handlers = provider.class.new(config).connection.builder.handlers

    refute_includes handlers.map(&:name), "Faraday::Response::Logger"
  end
end
