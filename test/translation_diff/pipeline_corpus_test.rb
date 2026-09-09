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

  # What Passage now hands a provider, which is where the four fixed inputs actually differ.
  def provider_texts(name)
    passage = TranslationDiff::Passage.new(PipelineCorpus::INPUTS.fetch(name),
                                           segmenter: TranslationDiff::Segmenters::Pragmatic.new)
    passage.segments.reject(&:empty?).map(&:core)
  end

  def self.method_name_for(name) = :"test_#{name.gsub(/[^a-zA-Z0-9]+/, '_')}"

  (PipelineCorpus::INPUTS.keys - PipelineCorpus::EXPECTED_TO_CHANGE).each do |name|
    define_method(method_name_for(name)) do
      assert_equal self.class.baseline_outputs.fetch(name), translated(name)
    end
  end

  # The four named in EXPECTED_TO_CHANGE, written out: the document each produces, and the texts a provider is sent.
  # The document is unchanged and has to stay so -- :null echoes, so an echoed document proves the round trip only.
  # What the rewrite fixes is the second half. The old path sends ["Salt &amp; pepper.", "Fine."] for the first,
  # ["Hard&nbsp;space here.", "Fine."] for the second, ["if a"] for the third and ["5", "6.", "True."] for the fourth.
  CHANGED = {
    "entity ampersand" => ["Salt &amp; pepper. Fine.", ["Salt & pepper.", "Fine."]],
    "entity nbsp" => ["Hard&nbsp;space here. Fine.", ["Hard\u00A0space here.", "Fine."]],
    "bare less-than" => ["if a < b then stop. Fine.", ["if a < b then stop.", "Fine."]],
    "bare less-than and greater" => ["5 < 6 and 7 > 6. True.", ["5 < 6 and 7 > 6.", "True."]]
  }.freeze

  CHANGED.each do |name, (document, texts)|
    define_method(method_name_for(name)) do
      assert_equal document.inspect, translated(name)
      assert_equal texts, provider_texts(name)
    end
  end
end
