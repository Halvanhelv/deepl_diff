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

  def passage(name)
    TranslationDiff::Passage.new(PipelineCorpus::INPUTS.fetch(name),
                                 segmenter: TranslationDiff::Segmenters::Pragmatic.new)
  end

  # What Passage now hands a provider, which is where the fixed inputs actually differ.
  def provider_texts(name) = passage(name).segments.reject(&:empty?).map(&:core)

  # Nothing translated, so the document owes its caller the bytes it arrived as.
  def untranslated_render(name) = passage(name).render

  # Every sentence back as it was sent, which is what :null does -- the new pipeline's answer to the document column.
  def echoed_render(name)
    subject = passage(name)
    subject.segments.reject(&:empty?).each { |segment| segment.translation = segment.core }
    subject.render
  end

  def self.method_name_for(name) = :"test_#{name.gsub(/[^a-zA-Z0-9]+/, '_')}"

  (PipelineCorpus::INPUTS.keys - PipelineCorpus::EXPECTED_TO_CHANGE).each do |name|
    define_method(method_name_for(name)) do
      assert_equal self.class.baseline_outputs.fetch(name), translated(name)
    end
  end

  # The names in EXPECTED_TO_CHANGE, written out: the texts a provider is sent, what TranslationDiff.translate
  # returns end to end, and Passage's render round trip -- byte-exact untranslated, equivalent markup once every
  # sentence is back. document: and echoed: are independent literals, kept apart even where they agree, so a
  # regression in either translate or render is caught by its own assertion rather than by one value checked twice.
  # The pipeline this replaced sent ["Salt &amp; pepper.", "Fine."] for the first, ["Hard&nbsp;space here.", "Fine."]
  # for the second, ["if a"] for the third, ["5", "6.", "True."] for the fourth and ["a"] for the fifth.
  CHANGED = {
    "entity ampersand" => {
      texts: ["Salt & pepper.", "Fine."],
      document: "Salt &amp; pepper. Fine.",
      echoed: "Salt &amp; pepper. Fine."
    },
    "entity nbsp" => {
      texts: ["Hard\u00A0space here.", "Fine."],
      # The entity is spelled as the character it means, which is the same document to a browser and not the same bytes.
      document: "Hard\u00A0space here. Fine.",
      echoed: "Hard\u00A0space here. Fine."
    },
    "bare less-than" => {
      texts: ["if a < b then stop.", "Fine."],
      document: "if a < b then stop. Fine.",
      echoed: "if a < b then stop. Fine."
    },
    "bare less-than and greater" => {
      texts: ["5 < 6 and 7 > 6.", "True."],
      document: "5 < 6 and 7 > 6. True.",
      echoed: "5 < 6 and 7 > 6. True."
    },
    # The recorded limit: `<b` is read as a tag, so the sentence after it is markup and never reaches a provider.
    "bare less-than before a letter" => {
      texts: ["a"],
      document: "a <b then stop. Fine.",
      echoed: "a <b then stop. Fine."
    }
  }.freeze

  CHANGED.each do |name, expected|
    define_method(method_name_for(name)) do
      assert_equal expected[:texts], provider_texts(name)
      assert_equal expected[:document].inspect, translated(name)
      assert_equal PipelineCorpus::INPUTS.fetch(name), untranslated_render(name)
      assert_equal expected[:echoed], echoed_render(name)
    end
  end

  # Without this, a sixth name in EXPECTED_TO_CHANGE would be subtracted from the generic loop and tested by neither.
  def test_every_expected_change_is_actually_asserted
    assert_equal PipelineCorpus::EXPECTED_TO_CHANGE.sort, CHANGED.keys.sort
  end
end
