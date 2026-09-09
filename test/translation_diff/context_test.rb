# frozen_string_literal: true

require "test_helper"

class ContextTest < Minitest::Test
  def setup
    TranslationDiff.reset!
    TranslationDiff.configure do |c|
      c.provider = :null
      # Pinned so a developer with REDIS_URL set doesn't have these tests reach for a socket.
      c.cache = :memory
    end
  end

  def teardown = TranslationDiff.reset!

  def test_a_context_does_not_change_the_global_configuration
    TranslationDiff.context { |c| c.cache_namespace = "tenant" }

    assert_equal "translation-diff", TranslationDiff.config.cache_namespace
  end

  def test_a_context_carries_the_values_it_was_given
    context = TranslationDiff.context { |c| c.cache_namespace = "tenant" }

    assert_equal "tenant", context.config.cache_namespace
  end

  def test_a_context_inherits_values_from_the_global_configuration
    TranslationDiff.config.cache_ttl = 42
    context = TranslationDiff.context { |c| c.cache_namespace = "tenant" }

    assert_equal 42, context.config.cache_ttl
  end

  def test_two_contexts_build_separate_collaborators
    one = TranslationDiff.context { |c| c.cache_namespace = "one" }
    two = TranslationDiff.context { |c| c.cache_namespace = "two" }

    refute_same one.config.cache_store, two.config.cache_store
  end

  def test_a_context_translates_through_its_own_configuration
    context = TranslationDiff.context do |c|
      c.provider = TranslationDiff::Providers::Null.new(TranslationDiff::Configuration.new)
    end

    assert_equal "Hello.", context.translate("Hello.", from: "en", to: "ru")
  end
end
