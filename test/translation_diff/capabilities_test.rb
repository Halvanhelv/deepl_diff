# frozen_string_literal: true

require "test_helper"

class CapabilitiesTest < Minitest::Test
  def capabilities(**overrides)
    TranslationDiff::Capabilities.new(max_request_size: 5_000, max_batch_size: 128, max_text_size: nil,
                                      html: :format, notranslate: true, detects_language: true,
                                      reports_billing: false, **overrides)
  end

  # Every reader asks a yes-or-no question, and Data.define generates plain
  # readers. Declaring the predicates once stops the codebase from asking
  # `detects_language` in one place and `detects_language?` in another.
  def test_it_answers_in_predicates
    assert_predicate capabilities, :html?
    assert_predicate capabilities, :notranslate?
    assert_predicate capabilities, :detects_language?
    refute_predicate capabilities, :reports_billing?
  end

  # `html` holds the name of the provider option that turns HTML on, which is
  # different for every vendor, so :none is the only way to say "cannot".
  def test_html_is_false_only_when_the_provider_has_no_html_mode
    refute_predicate capabilities(html: :none), :html?
    assert_predicate capabilities(html: :tag_handling), :html?
  end

  def test_it_is_frozen_so_a_provider_cannot_be_mutated_at_runtime
    assert_predicate capabilities, :frozen?
  end
end
