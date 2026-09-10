require "test_helper"

class TranslationDiffTest < ConfiguredTest
  def setup
    super
    TranslationDiff.configure do |c|
      c.provider = :null
      # Pinned so a developer with REDIS_URL set doesn't have these tests reach for a socket.
      c.cache = :memory
    end
  end

  def test_has_a_version_number
    refute_nil TranslationDiff::VERSION
  end

  def test_the_default_segmenter_is_pragmatic
    assert_instance_of TranslationDiff::Segmenters::Pragmatic, TranslationDiff.config.segmenter_instance
  end

  # The entry point builds a Translator, so a nested value comes back with its shape and its non-strings intact.
  def test_translate_runs_the_values_through_the_pipeline
    result = TranslationDiff.translate({ title: "One. Two.", count: 42 }, from: "en", to: "ru")

    assert_equal({ title: "One. Two.", count: 42 }, result)
  end

  # A caller who splats the same options hash into every call must get the same hash back out of it.
  def test_repeated_calls_leave_the_callers_options_hash_alone
    options = { from: :en, to: :ru }

    2.times { assert_equal "Some string.", TranslationDiff.translate("Some string.", **options) }

    assert_equal({ from: :en, to: :ru }, options)
  end

  # `to:` still defaults to nil in the signature, so the keyword it names is what the caller has to read.
  def test_a_missing_target_language_is_refused_by_name
    error = assert_raises(ArgumentError) { TranslationDiff.translate("One.", from: "en") }

    assert_match(/to:/, error.message)
  end
end
