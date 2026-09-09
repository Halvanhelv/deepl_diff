require "pragmatic_segmenter"

# Default segmenter: scores 76/80 on the Golden Rules corpus vs Simple's 47/80 (golden_rules_test.rb).
class TranslationDiff::Segmenters::Pragmatic
  # Raised only if computed offsets violate their own postcondition, never by ordinary sentence rewriting.
  class Error < TranslationDiff::Error; end

  # Without a language, Russian mis-segments: it treats "Проф." as a full sentence and stops there.
  DEFAULT_LANGUAGE = "en".freeze

  # A lone "\n" is incidental source formatting, not a paragraph break; a run of two or more is left alone.
  SINGLE_NEWLINE = /(?<!\n)\n(?!\n)/

  def self.build(_config) = new

  def split_offsets(text, language: nil)
    return [0] unless split_candidate?(text)

    shadow = shadow_newlines(text)
    sentences = segment(shadow, language)
    return [0] if sentences.size <= 1

    offsets = recover_offsets(shadow, sentences)
    assert_valid_offsets(text, offsets)
    offsets
  end

  private

  def split_candidate?(text)
    text.is_a?(String) && !text.strip.empty?
  end

  # pragmatic_segmenter treats any single newline as a sentence boundary, confirmed false on wrapped prose.
  def shadow_newlines(text)
    text.gsub(SINGLE_NEWLINE, " ")
  end

  # DeepL sends codes like "EN-GB"; the lookup is case-sensitive, so without this "RU" falls through to Common.
  def normalize_language(language)
    code = language.to_s.downcase.split(/[-_]/, 2).first
    return DEFAULT_LANGUAGE unless PragmaticSegmenter::Languages::LANGUAGE_CODES.key?(code)

    code
  end

  def segment(shadow, language)
    PragmaticSegmenter::Segmenter.new(text: shadow, language: normalize_language(language)).segment
  end

  # Pinned 0.3.24's cleaner rewrites text (collapses spaces, respaces "Ph.D."), so some sentences can't be located.
  def recover_offsets(shadow, sentences)
    starts, cursor, stopped_early = walk(shadow, sentences)

    # The first located sentence's own start is never a split point; only the ones after it are.
    offsets = [0] + starts.drop(1)

    # Cursor is verified evidence, not a guess; guarded against both ways it could break the offsets invariant.
    offsets << cursor if stopped_early && cursor < shadow.length && cursor > offsets.last

    offsets
  end

  # Returns the starts of every sentence located, the cursor after the last one, and whether the walk stopped early.
  def walk(shadow, sentences)
    cursor = 0
    starts = []

    sentences.each do |sentence|
      match = locate(shadow, sentence, cursor)
      next if match == :skip
      return [starts, cursor, true] if match.nil?

      starts << match[0]
      cursor = match[1]
    end

    [starts, cursor, false]
  end

  # :skip for empty (an empty match would never advance the cursor); nil if a non-empty sentence isn't found.
  def locate(shadow, sentence, cursor)
    return :skip if sentence.empty?

    start = shadow.index(sentence, cursor)
    return nil if start.nil?

    [start, start + sentence.length]
  end

  # Asserts the postcondition rather than trusting construction forever: a wrong offset would silently corrupt.
  def assert_valid_offsets(text, offsets)
    return if offsets.first.zero? &&
              offsets.each_cons(2).all? { |a, b| a < b } &&
              offsets.all? { |offset| offset < text.length }

    raise Error, "computed offsets #{offsets.inspect} do not start at 0, strictly increase, and stay " \
                 "within the text -- refusing to hand them back. text: #{text.inspect}"
  end
end

TranslationDiff::Segmenters.registry.register(:pragmatic, TranslationDiff::Segmenters::Pragmatic)
