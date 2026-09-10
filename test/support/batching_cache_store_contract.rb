# The optional half of the cache store contract -- include only in a store that implements write_multi.
module BatchingCacheStoreContract
  def test_write_multi_writes_every_pair
    store.write_multi([%w[a one], %w[b two]])

    assert_equal %w[one two], store.read_multi(%w[a b])
  end

  def test_write_multi_of_no_pairs_writes_nothing
    store.write_multi([])

    assert_empty store.read_multi([])
  end

  def test_write_multi_replaces_a_key_written_before
    store.write("a", "one")
    store.write_multi([%w[a two]])

    assert_equal ["two"], store.read_multi(["a"])
  end
end
