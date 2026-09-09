require "test_helper"

class DocumentTest < Minitest::Test
  def map(value, &) = TranslationDiff::Document.new(value).map(&)

  def test_a_bare_string_is_mapped
    assert_equal "HELLO", map("hello", &:upcase)
  end

  def test_a_hash_keeps_its_keys_and_their_order
    result = map({ title: "one", body: "two" }, &:upcase)

    assert_equal({ title: "ONE", body: "TWO" }, result)
    assert_equal %i[title body], result.keys
  end

  def test_an_array_keeps_its_order
    assert_equal %w[A B C], map(%w[a b c], &:upcase)
  end

  def test_nesting_of_both_kinds_survives
    value = { a: ["one", { b: "two" }], c: "three" }

    assert_equal({ a: ["ONE", { b: "TWO" }], c: "THREE" }, map(value, &:upcase))
  end

  # Anything that is not a String is not translatable and must arrive on the
  # other side as the same object, in the same place.
  def test_non_strings_pass_through_untouched
    value = { text: "one", count: 42, missing: nil, flag: true, at: :symbol }

    assert_equal({ text: "ONE", count: 42, missing: nil, flag: true, at: :symbol },
                 map(value, &:upcase))
  end

  def test_the_block_is_not_called_for_non_strings
    seen = []
    map({ text: "one", count: 42, missing: nil }) do |s|
      seen << s
      s
    end

    assert_equal ["one"], seen
  end

  def test_an_empty_string_is_still_a_string
    assert_equal [""], TranslationDiff::Document.new([""]).strings
  end

  def test_strings_are_returned_in_document_order
    value = { a: ["one", { b: "two" }], c: "three" }

    assert_equal %w[one two three], TranslationDiff::Document.new(value).strings
  end

  def test_strings_does_not_modify_the_value
    value = { a: ["one"] }
    TranslationDiff::Document.new(value).strings

    assert_equal({ a: ["one"] }, value)
  end

  # The caller's structure is theirs. Mapping returns a new one.
  def test_map_does_not_mutate_the_original
    value = { a: ["one"] }
    map(value, &:upcase)

    assert_equal({ a: ["one"] }, value)
  end

  def test_deep_nesting_does_not_lose_its_shape
    value = [[[["deep"]]]]

    assert_equal [[[["DEEP"]]]], map(value, &:upcase)
  end
end
