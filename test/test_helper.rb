# frozen_string_literal: true

require "simplecov"

SimpleCov.start

require "translation_diff"

require "minitest/autorun"

# Stands in for a connection_pool: the gem only ever calls #with on whatever it is handed.
class FakeConnectionPool
  def initialize(connection)
    @connection = connection
  end

  def with
    yield @connection
  end
end

# Any test that configures anything must reset afterwards, or its settings leak into later tests.
class ConfiguredTest < Minitest::Test
  def setup = TranslationDiff.reset!
  def teardown = TranslationDiff.reset!
end
