# frozen_string_literal: true

require "test_helper"

class RegistryTest < Minitest::Test
  Buildable = Struct.new(:config) do
    def self.build(config) = new(config)
  end

  def setup
    @registry = TranslationDiff::Registry.new("widget")
  end

  def test_building_a_registered_name_calls_build_on_the_class
    @registry.register(:thing, Buildable)

    built = @registry.build(:thing, :the_config)

    assert_instance_of Buildable, built
    assert_equal :the_config, built.config
  end

  def test_a_name_registered_as_a_string_is_reachable_as_a_symbol
    @registry.register("thing", Buildable)

    assert_instance_of Buildable, @registry.build(:thing, nil)
  end

  def test_an_unknown_name_raises_naming_the_kind_and_what_is_registered
    @registry.register(:alpha, Buildable)
    @registry.register(:beta, Buildable)

    error = assert_raises(TranslationDiff::Error) { @registry.build(:missing, nil) }

    assert_includes error.message, "widget"
    assert_includes error.message, ":missing"
    assert_includes error.message, "alpha"
    assert_includes error.message, "beta"
  end

  def test_names_lists_registrations_in_order
    @registry.register(:alpha, Buildable)
    @registry.register(:beta, Buildable)

    assert_equal %i[alpha beta], @registry.names
  end

  def test_registered_answers_for_both_present_and_absent_names
    @registry.register(:alpha, Buildable)

    assert @registry.registered?(:alpha)
    refute @registry.registered?(:beta)
  end
end
