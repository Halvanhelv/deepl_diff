# frozen_string_literal: true

require "test_helper"

class ContextTest < Minitest::Test
  # TranslationDiff::Providers::Null now speaks Translation::Request/Response
  # (provider-transport work); request.rb still calls a provider the old way
  # and is migrated onto the new contract in a later task. This double keeps
  # that old shape so this file can keep exercising Context#translate without
  # touching request.rb.
  class NullDouble
    # rubocop:disable-next Lint/UnusedMethodArgument
    def translate(texts, from:, to:, **_options) = texts
    def max_request_size = 1_000_000
    def max_batch_size = 1_000_000
    def cache_key = "null"
  end

  def setup
    TranslationDiff.reset!
    TranslationDiff.configure do |c|
      c.provider = :null
      # Pinned rather than left to the default so a developer with REDIS_URL
      # set in their environment does not have these tests reach for a socket.
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
    context = TranslationDiff.context { |c| c.provider = NullDouble.new }

    assert_equal "Hello.", context.translate("Hello.", from: "en", to: "ru")
  end
end
