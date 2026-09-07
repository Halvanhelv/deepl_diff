# frozen_string_literal: true

require "pragmatic_segmenter"

# Splits a string into sentence-sized cache units using the
# `pragmatic_segmenter` gem's per-language rule sets. This is the default
# segmenter: measured against a sample of the Golden Rules corpus (79
# exemplars across 10 languages, from the pragmatic_segmenter project
# itself; see test/translation_diff/golden_rules_test.rb), this class scores
# 76/80 against TranslationDiff::Segmenters::Simple's 47/80 on the same
# corpus -- and the gap is worst on exactly the languages Simple cannot
# reason about at all: Arabic, Hindi, Armenian, Greek, because they have no
# letter case for Simple's central "does the next letter look lowercase"
# rule to use. (The `pragmatic_segmenter` library itself scores 78/80 on
# this corpus; the two-point difference is not a bug here -- it is 2
# exemplars where the library's cleaner silently rewrites the source, e.g.
# deleting a raw newline it treats as a PDF line-wrap artefact, which this
# class refuses to do invisibly. See #recover_offsets.)
#
# `pragmatic_segmenter` returns sentence strings, not offsets, and drops the
# whitespace between them. This gem reassembles the source document from
# offsets (see TranslationDiff::Segmenters::Simple), so the strings have to
# be turned back into split points by finding each one in the source, in
# order, starting the search where the previous one left off.
class TranslationDiff::Segmenters::Pragmatic
  class Error < TranslationDiff::Error; end

  # pragmatic_segmenter defaults to English rules when no language is given.
  # Without this, Russian (among others) mis-segments: it treats "Проф." as
  # a full sentence and stops there instead of reading through to the next
  # real terminator. Passing the caller's language avoids that; see
  # TranslationDiff::Request for where the language comes from and why it is
  # sometimes nil despite this.
  DEFAULT_LANGUAGE = "en"

  def split_offsets(text, language: nil)
    return [0] unless split_candidate?(text)

    sentences = segment(text, language)
    return [0] if sentences.size <= 1

    recover_offsets(text, sentences)
  end

  private

  def split_candidate?(text)
    text.is_a?(String) && !text.strip.empty?
  end

  def segment(text, language)
    PragmaticSegmenter::Segmenter.new(text: text, language: language || DEFAULT_LANGUAGE).segment
  end

  # Recovers split points by scanning the source for each sentence
  # pragmatic_segmenter returned, in order, each search starting where the
  # previous sentence's match ended. This is only valid because the sentences
  # are known (measured, not assumed) to appear verbatim and in order in the
  # source -- but that is a property of a third-party library's output, not
  # a guarantee, so a sentence that cannot be found raises rather than
  # silently falling back to something plausible. A silent fallback here
  # would corrupt the document: offsets feed straight into slicing the
  # original text back apart.
  #
  # This is not hypothetical: pragmatic_segmenter's cleaner treats some raw
  # newlines as PDF line-wrap noise and deletes them outright (e.g. Japanese
  # deletes a "\n" that follows "の", a very common particle). A single-
  # sentence node absorbs that silently -- there is nothing to recover, so
  # the original text passes through untouched -- but once a second sentence
  # follows, the cleaned sentence pragmatic_segmenter handed back no longer
  # appears in the source at all, and this raises instead of guessing.
  def recover_offsets(text, sentences)
    offsets = [0]
    cursor = 0

    sentences.each_with_index do |sentence, index|
      start = text.index(sentence, cursor)
      raise Error, not_found_message(text, sentence) if start.nil?

      offsets << start unless index.zero?
      cursor = start + sentence.length
    end

    offsets
  end

  def not_found_message(text, sentence)
    "pragmatic_segmenter returned a sentence that cannot be located in its " \
      "source text, in order, from the end of the previous match -- refusing " \
      "to guess at offsets. sentence: #{sentence.inspect}, text: #{text.inspect}"
  end
end
