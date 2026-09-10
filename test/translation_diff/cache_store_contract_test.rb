require "test_helper"
require "support/cache_store_contract"

class CacheStoreContractTest < Minitest::Test
  include CacheStoreContract

  # Exactly the two required methods, nothing else -- proves the required contract never needs write_multi.
  class MinimalStore
    def initialize = @entries = {}
    def read_multi(keys) = keys.map { |key| @entries[key] }
    def write(key, value) = @entries[key] = value
  end

  attr_reader :store

  def setup
    @store = MinimalStore.new
  end
end
