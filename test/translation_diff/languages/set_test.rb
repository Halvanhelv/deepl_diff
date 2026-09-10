require "test_helper"
require "tmpdir"

class LanguagesSetTest < Minitest::Test
  def test_a_corrupt_file_raises_naming_the_path_and_the_parsers_own_message
    Dir.mktmpdir do |dir|
      path = File.join(dir, "broken.json")
      File.write(path, "not json at all")
      parser_message = parser_message_for("not json at all")

      error = assert_raises(TranslationDiff::Error) { TranslationDiff::Languages::Set.load(path) }

      assert_includes error.message, path
      assert_includes error.message, parser_message
    end
  end

  def parser_message_for(garbage)
    JSON.parse(garbage)
  rescue JSON::ParserError => e
    e.message
  end

  def set(codes)
    TranslationDiff::Languages::Set.new(provider: "x", captured_at: "2026-01-01", endpoint: "",
                                        source: codes, target: codes)
  end

  # A vendor publishing the individual code has, by definition, covered the macro it belongs to.
  def test_a_macro_code_matches_a_vendor_that_only_publishes_the_individual_code
    assert set(%w[en pes]).supports_target?("fa")
  end

  # The reverse does not hold: a vendor publishing only the macro has not promised the individual.
  def test_an_individual_code_does_not_match_a_vendor_that_only_publishes_the_macro
    refute set(%w[en zh]).supports_target?("cmn")
  end
end
