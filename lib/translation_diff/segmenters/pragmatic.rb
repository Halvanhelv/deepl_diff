# frozen_string_literal: true

require "pragmatic_segmenter"

# Splits a string into sentence-sized cache units using the
# `pragmatic_segmenter` gem's per-language rule sets. This is the default
# segmenter: measured against a sample of the Golden Rules corpus (79
# exemplars across 10 languages, from the pragmatic_segmenter project
# itself; see test/translation_diff/golden_rules_test.rb), this class scores
# 75/80 against TranslationDiff::Segmenters::Simple's 47/80 on the same
# corpus -- and the gap is worst on exactly the languages Simple cannot
# reason about at all: Arabic, Hindi, Armenian, Greek, because they have no
# letter case for Simple's central "does the next letter look lowercase"
# rule to use. (The `pragmatic_segmenter` library itself scores 78/80 on
# this corpus. The three-point difference is not a bug -- two exemplars are
# ones where the library's cleaner silently rewrites the source, e.g.
# deleting a raw newline it treats as a PDF line-wrap artefact, which this
# class refuses to do invisibly; see #recover_offsets. The third is the
# deliberate cost of newline shadowing below: one English exemplar shaped
# like a bare, punctuation-free list separated by single newlines segments
# as one unit instead of three. That shape does not arise in this gem's
# actual input -- HTML list items are separated by markup into distinct text
# nodes already, so a newline inside one text node is incidental source
# formatting, essentially always -- and it is a missed boundary, the
# harmless direction, traded away to close a false-split error class that
# does arise in real input. See #shadow_newlines.)
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

  # A single newline -- one with neither a preceding nor a following "\n" --
  # is incidental source formatting almost everywhere this gem is used (HTML
  # indentation, hand-wrapped prose), not a paragraph break. A run of two or
  # more newlines is left alone: that is a real paragraph break, and
  # pragmatic_segmenter already handles it correctly. See #shadow_newlines.
  SINGLE_NEWLINE = /(?<!\n)\n(?!\n)/

  def split_offsets(text, language: nil)
    return [0] unless split_candidate?(text)

    shadow = shadow_newlines(text)
    sentences = segment(shadow, language)
    return [0] if sentences.size <= 1

    recover_offsets(text, shadow, sentences)
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
  # shadow is guaranteed the same length as the source and every offset
  # recovered from it is valid in the source too -- the guard below asserts
  # that rather than assuming it, so a future change to the substitution
  # cannot silently corrupt a document.
  def shadow_newlines(text)
    shadow = text.gsub(SINGLE_NEWLINE, " ")
    return shadow if shadow.length == text.length

    raise Error, "newline shadowing changed the text length (#{text.length} -> " \
                 "#{shadow.length}) -- refusing to recover offsets against a " \
                 "shadow of a different shape than the source. text: #{text.inspect}"
  end

  def segment(shadow, language)
    PragmaticSegmenter::Segmenter.new(text: shadow, language: language || DEFAULT_LANGUAGE).segment
  end

  # Recovers split points by scanning the shadow for each sentence
  # pragmatic_segmenter returned, in order, each search starting where the
  # previous sentence's match ended. This is only valid because the
  # sentences are known (measured, not assumed) to appear verbatim and in
  # order in the shadow -- but that is a property of a third-party library's
  # output, not a guarantee, so a sentence that cannot be found raises
  # rather than silently falling back to something plausible. A silent
  # fallback here would corrupt the document: offsets feed straight into
  # slicing the original text back apart.
  #
  # Shadowing shrinks this raise's surface (it fixed the one confirmed real
  # trigger -- see test/translation_diff/segmenters/pragmatic_test.rb) but
  # does not make it unreachable: it protects only against this gem's own
  # newline-related assumptions, not against whatever else a future
  # pragmatic_segmenter release's cleaner might rewrite.
  def recover_offsets(text, shadow, sentences)
    offsets = [0]
    cursor = 0

    sentences.each_with_index do |sentence, index|
      start = shadow.index(sentence, cursor)
      raise Error, not_found_message(text, sentence) if start.nil?

      offsets << start unless index.zero?
      cursor = start + sentence.length
    end

    offsets
  end

  def not_found_message(text, sentence)
    "pragmatic_segmenter returned a sentence that cannot be located, in order, " \
      "in the newline-shadowed source text -- refusing to guess at offsets. " \
      "sentence: #{sentence.inspect}, text: #{text.inspect}"
  end
end
