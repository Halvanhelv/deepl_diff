# frozen_string_literal: true

require "test_helper"

class TranslationDiffTest < ConfiguredTest
  def test_has_a_version_number
    refute_nil TranslationDiff::VERSION
  end

  def test_the_default_segmenter_is_pragmatic
    assert_instance_of TranslationDiff::Segmenters::Pragmatic, TranslationDiff.config.segmenter_instance
  end
end
