require "test_helper"
require "support/pipeline_corpus"

# Judges the pipeline rewrite against the baseline captured in ~/JetRockets/.deepl_diff-specs/pipeline-baseline.txt
# before any of the pipeline changed, translating every input the same way the baseline script did: through the
# :null provider, from "en" to "ru".
class PipelineCorpusTest < ConfiguredTest
  BASELINE_PATH = File.expand_path("~/JetRockets/.deepl_diff-specs/pipeline-baseline.txt")

  def self.baseline_outputs
    @baseline_outputs ||= File.read(BASELINE_PATH).scan(/^=== (.+) ===\nOUTPUT: (.*)\n/).to_h
  end

  def translated(name)
    TranslationDiff.translate(PipelineCorpus::INPUTS.fetch(name), from: "en", to: "ru", provider: :null).inspect
  end

  def self.method_name_for(name) = :"test_#{name.gsub(/[^a-zA-Z0-9]+/, '_')}"

  (PipelineCorpus::INPUTS.keys - PipelineCorpus::EXPECTED_TO_CHANGE).each do |name|
    define_method(method_name_for(name)) do
      assert_equal self.class.baseline_outputs.fetch(name), translated(name)
    end
  end

  # These four are named in EXPECTED_TO_CHANGE: the rewrite is scheduled to fix them, not to leave them alone.
  # Skipped, not deleted -- a later task removes the skip and then this asserts the fixed output differs from
  # today's recorded baseline.
  PipelineCorpus::EXPECTED_TO_CHANGE.each do |name|
    define_method(method_name_for(name)) do
      skip "scheduled to change: a later task removes this skip once the rewrite fixes this input " \
           "(see PipelineCorpus::EXPECTED_TO_CHANGE)"
      refute_equal self.class.baseline_outputs.fetch(name), translated(name)
    end
  end
end
