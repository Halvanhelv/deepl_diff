require "test_helper"

class LeavesTest < Minitest::Test
  def collapse(value) = TranslationDiff::Leaves.collapse_nils(value)

  def count(value) = TranslationDiff::Leaves.count(value)

  def test_a_nested_nil_becomes_an_empty_string
    assert_equal({ a: "one", skip: "" }, collapse({ a: "one", skip: nil }))
    assert_equal ["one", "", 42], collapse(["one", nil, 42])
  end

  def test_a_bare_nil_becomes_an_empty_string_too
    assert_equal "", collapse(nil)
  end

  def test_every_other_leaf_is_handed_back_as_it_is
    assert_equal({ a: "one", n: 42, f: false }, collapse({ a: "one", n: 42, f: false }))
  end

  def test_the_caller_s_own_structure_is_never_modified
    value = { a: "one", nested: ["two", nil] }
    collapse(value)

    assert_equal({ a: "one", nested: ["two", nil] }, value)
  end

  def test_counting_covers_every_leaf_whatever_its_type
    assert_equal 3, count({ a: "one", n: 42, skip: nil })
    assert_equal 5, count({ a: "one", b: { c: "two", d: [1, "three", nil] } })
  end

  def test_a_scalar_is_one_leaf_and_an_empty_container_is_none
    assert_equal 1, count("one")
    assert_equal 1, count(nil)
    assert_equal 0, count([])
    assert_equal 0, count({})
  end
end
