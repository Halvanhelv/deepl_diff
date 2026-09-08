# frozen_string_literal: true

# The executable form of the cache store contract. Every store includes this
# and defines #store; anything that passes can be TranslationDiff's cache.
module CacheStoreContract
  def test_write_then_read_multi_returns_the_value
    store.write("a", "one")

    assert_equal ["one"], store.read_multi(["a"])
  end

  def test_read_multi_returns_nil_for_a_missing_key_in_position
    store.write("b", "two")

    assert_equal [nil, "two", nil], store.read_multi(%w[a b c])
  end

  def test_read_multi_of_no_keys_returns_no_values
    assert_empty store.read_multi([])
  end

  def test_writing_the_same_key_twice_keeps_the_second_value
    store.write("a", "one")
    store.write("a", "two")

    assert_equal ["two"], store.read_multi(["a"])
  end
end
