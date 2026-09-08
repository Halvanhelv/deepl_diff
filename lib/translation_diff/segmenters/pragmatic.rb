# frozen_string_literal: true

require "pragmatic_segmenter"

# Splits a string into sentence-sized cache units using the
# `pragmatic_segmenter` gem's per-language rule sets. This is the default
# segmenter: measured against the Golden Rules corpus -- the
# `context "Golden Rules" do` block of each of the 10 per-language spec
# files on diasks2/pragmatic_segmenter, 80 exemplars in total; a sample of
# the same corpus is in test/translation_diff/golden_rules_test.rb -- this
# class scores 76/80 against TranslationDiff::Segmenters::Simple's 47/80 on
# the same corpus -- and the gap is worst on exactly the languages Simple
# cannot reason about at all: Arabic, Hindi, Armenian, Greek, because they
# have no letter case for Simple's central "does the next letter look
# lowercase" rule to use.
#
# `pragmatic_segmenter` returns sentence strings, not offsets, and drops the
# whitespace between them. This gem reassembles the source document from
# offsets (see TranslationDiff::Segmenters::Simple), so the strings have to
# be turned back into split points by finding each one in the source, in
# order, starting the search where the previous one left off.
#
# That recovery is only as good as the assumption that each returned
# sentence still appears verbatim in the text pragmatic_segmenter was given
# -- and pinned version 0.3.24's cleaner does not preserve that in every
# case. It collapses runs of three or more spaces inside a sentence, it
# respaces "Ph.D." into "Ph. D.", and (language-specific) its Japanese rules
# delete a "\n" that follows "の". None of these are rare: an English
# sentence mentioning a degree, or HTML indented with more than two spaces,
# hits one of them routinely. #recover_offsets does not raise when this
# happens. It recovers every offset it can verify, in order, and stops at
# the first sentence it cannot -- but the boundary at the end of the last
# sentence it did verify is not thrown away with the rest: it was matched
# character for character, so it is still emitted, and only the genuinely
# unverifiable remainder becomes one final unit. This is a coarsening, not
# a fallback: every offset this class ever emits has been proved to exist
# at that position in the source, so the document reassembles exactly
# either way -- the last cache unit is just bigger when recovery stops
# early, not the whole node.
class TranslationDiff::Segmenters::Pragmatic
  # Raised only if #split_offsets itself computed offsets that violate its
  # own postcondition (start at 0, strictly increasing, all within the
  # text) -- not by ordinary use of pragmatic_segmenter, however it rewrites
  # a sentence. Kept as public API: it is documented in the README's error
  # tree, and a caller may already rescue it.
  class Error < TranslationDiff::Error; end

  # pragmatic_segmenter defaults to English rules when no language is given.
  # Without this, Russian (among others) mis-segments: it treats "Проф." as
  # a full sentence and stops there instead of reading through to the next
  # real terminator. Passing the caller's language avoids that; see
  # TranslationDiff::Request for where the language comes from and why it is
  # sometimes nil despite this.
  DEFAULT_LANGUAGE = "en"

  # A single newline -- one with neither a preceding nor a following "\n" --
  # is incidental source formatting almost everywhere this gem is used (HTML
  # indentation, hand-wrapped prose), not a paragraph break. A run of two or
  # more newlines is left alone: that is a real paragraph break, and
  # pragmatic_segmenter already handles it correctly. See #shadow_newlines.
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

  # pragmatic_segmenter treats essentially any single newline as a sentence
  # boundary candidate, independent of punctuation -- confirmed on
  # completely ordinary, punctuation-free, line-wrapped prose with
  # whitespace on both sides of the newline, not just a newline glued to
  # non-whitespace. That is a false split, the harmful kind of error this
  # whole gem exists to avoid, and it is common: HTML text nodes routinely
  # carry incidental newlines from source formatting.
  #
  # The fix is to segment a shadow copy with single newlines replaced by a
  # single space, then recover offsets against that shadow and slice the
  # *original* text at them. "\n" and " " are both one character, so the
  # shadow is always the same length as the source and every offset
  # recovered from it is a valid index into the source too -- there is no
  # length check here because a one-character-for-one-character `gsub`
  # cannot produce one; #assert_valid_offsets checks the postcondition this
  # class actually depends on instead.
  def shadow_newlines(text)
    text.gsub(SINGLE_NEWLINE, " ")
  end

  # Normalises a caller-supplied language code to one pragmatic_segmenter
  # actually has rules for: downcased, with any region subtag dropped
  # (DeepL, this gem's own flagship provider, sends uppercase codes such as
  # "EN" and "EN-GB"; PragmaticSegmenter::Languages.get_language_by_code is
  # case-sensitive and knows nothing about region subtags, so "RU" and
  # "ru-RU" would otherwise silently fall through to Common, not even to the
  # documented English fallback). An unrecognised code, once normalised,
  # falls back to DEFAULT_LANGUAGE explicitly, landing on English rules
  # rather than on Common.
  def normalize_language(language)
    code = language.to_s.downcase.split(/[-_]/, 2).first
    return DEFAULT_LANGUAGE unless PragmaticSegmenter::Languages::LANGUAGE_CODES.key?(code)

    code
  end

  def segment(shadow, language)
    PragmaticSegmenter::Segmenter.new(text: shadow, language: normalize_language(language)).segment
  end

  # Recovers split points by scanning the shadow for each sentence
  # pragmatic_segmenter returned, in order, each search starting where the
  # previous sentence's match ended. Every sentence located this way
  # contributes a verified offset. The first sentence that cannot be
  # located -- because pragmatic_segmenter's cleaner rewrote it, see the
  # class comment -- ends the walk, but the boundary at the end of the last
  # sentence that *was* located is not a guess: it was matched character
  # for character, so it is emitted too (guarded below), and only the
  # genuinely unverifiable remainder becomes one final unit rather than
  # being sliced on a guess.
  #
  # An empty sentence is skipped rather than walked into: an empty match
  # would otherwise emit the same offset twice in a row (a non-increasing
  # "boundary" that is not a boundary at all) and could stall the cursor
  # forever. See #locate.
  def recover_offsets(shadow, sentences)
    starts, cursor, stopped_early = walk(shadow, sentences)

    # The first located sentence's own start is never a split point -- it is
    # where offset 0 already covers -- only the ones after it are.
    offsets = [0] + starts.drop(1)

    # The walk stopped before exhausting every sentence, so cursor -- the end
    # of the last one actually matched -- is verified evidence, not a guess.
    # Emitting it is what turns "the whole node becomes one unit" into "the
    # verified prefix is sliced off, only the rest is coarsened". Guarded
    # against the two ways this could break the offsets invariant: cursor
    # equal to the text's length (nothing left to slice, the last located
    # sentence already reaches the end) and cursor not advancing past the
    # last offset already emitted (nothing was located at all, so cursor is
    # still 0 -- the same as the leading offset already in the array).
    offsets << cursor if stopped_early && cursor < shadow.length && cursor > offsets.last

    offsets
  end

  # Walks the sentences in order, returning the starts of every one located
  # (see #locate), the cursor left after the last one located, and whether
  # the walk stopped before exhausting every sentence.
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

  # Returns [start, next_cursor] for a sentence found at or after cursor;
  # :skip for an empty sentence, which #recover_offsets passes over without
  # ending the walk (an empty pattern would "match" at cursor itself and
  # never advance past it -- distinct from not being found, which should
  # end the walk, not stall it); or nil if a non-empty sentence cannot be
  # found there at all, which does end the walk. A located non-empty
  # sentence always advances past cursor by construction (String#index
  # never returns a position before where the search started), so there is
  # no further case to guard here -- #assert_valid_offsets is the actual
  # backstop if that ever stops holding.
  def locate(shadow, sentence, cursor)
    return :skip if sentence.empty?

    start = shadow.index(sentence, cursor)
    return nil if start.nil?

    [start, start + sentence.length]
  end

  # The postcondition every caller of #split_offsets depends on: offsets
  # start at 0, strictly increase, and every one is a valid index into the
  # text. #recover_offsets is built to guarantee this by construction: this
  # asserts it rather than trusting that construction forever, since a wrong
  # offset here would silently corrupt the document it feeds back into.
  def assert_valid_offsets(text, offsets)
    return if offsets.first.zero? &&
              offsets.each_cons(2).all? { |a, b| a < b } &&
              offsets.all? { |offset| offset < text.length }

    raise Error, "computed offsets #{offsets.inspect} do not start at 0, strictly increase, and stay " \
                 "within the text -- refusing to hand them back. text: #{text.inspect}"
  end
end

TranslationDiff::Segmenters.registry.register(:pragmatic, TranslationDiff::Segmenters::Pragmatic)
