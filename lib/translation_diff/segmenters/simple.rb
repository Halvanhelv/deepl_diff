# frozen_string_literal: true

# Splits a string into sentence-sized cache units, with no runtime
# dependency beyond Ruby's own Unicode data.
#
# A wrong boundary never corrupts the document -- the tokenizer slices by
# offset and joins the pieces back together -- but the two kinds of error are
# not equal. A missed boundary just makes the cache unit bigger: still a
# coherent, correctly translated piece of text. A false boundary sends half a
# sentence to the provider on its own, and it comes back wrong. So this class
# is deliberately conservative: it only splits on strong signals, and every
# guard below exists to turn a would-be split back off, never to add one.
#
# Its central rule -- "the next visible character is lowercase, so do not
# split" -- has no meaning in scripts without case, such as Arabic, Hindi or
# Hebrew, so it fares worse than TranslationDiff::Segmenters::Pragmatic (the
# default) on those languages. It exists for callers who want zero extra
# dependencies and translate only from cased scripts.
class TranslationDiff::Segmenters::Simple
  # A period, question mark, exclamation mark or ellipsis, run together
  # (`?!`, `!!!`) so a whole run is treated as a single terminator; or a
  # run of CJK terminators, which need no trailing whitespace and no guards
  # -- those scripts have no case ambiguity and no abbreviation periods.
  TERMINATOR = /[.!?…]+|[。！？]+/

  CJK_TERMINATOR = /\A[。！？]/

  # A short list of words that end in "." without ending a sentence.
  # Matched case-insensitively against the word immediately before the
  # period. A caller can extend this constant to cover their own domain.
  ABBREVIATIONS = %w[
    т.е. т.д. т.п. см. рис. стр. гр. ул. г. руб. проф. акад. тыс. млн. млрд. им.
    Mr. Mrs. Ms. Dr. Prof. St. etc. e.g. i.e. vs. approx. No. im. fig. Fig. vol. p. pp.
  ].map(&:downcase).freeze

  # The trailing run of letters, digits and periods in a preceding word --
  # what is actually compared against ABBREVIATIONS and checked for being a
  # single initial. Strips leading punctuation such as an opening quote so
  # `"Dr. Smith` still guards on "Dr.".
  WORD_TAIL = /[\p{L}\p{N}.]+\z/

  def self.build(_config) = new

  # language: is part of the shared segmenter contract but is ignored here --
  # this segmenter's rules (case, digits, punctuation) are language-neutral.
  # rubocop:disable-next Lint/UnusedMethodArgument
  def split_offsets(text, language: nil)
    offsets = [0]
    position = 0

    while (match = TERMINATOR.match(text, position))
      boundary = boundary_for(text, match)
      offsets << boundary if boundary
      position = match.end(0)
    end

    offsets
  end

  private

  def boundary_for(text, match)
    if CJK_TERMINATOR.match?(match[0])
      cjk_boundary(text, match.end(0))
    else
      latin_boundary(text, match)
    end
  end

  # CJK terminators need no trailing whitespace to split, but if whitespace
  # does follow, it is attached to the sentence that just ended rather than
  # left as a leading gap on the next one.
  def cjk_boundary(text, run_end)
    boundary = skip_whitespace(text, run_end)
    boundary if boundary < text.length
  end

  # Latin terminators only count as a candidate when followed by whitespace;
  # a bare "." with nothing after it is not a sentence break, it is a string
  # that stops mid-thought.
  def latin_boundary(text, match)
    run_end = match.end(0)
    return unless whitespace?(text[run_end])

    boundary = skip_whitespace(text, run_end)
    return if boundary >= text.length
    return if guarded?(text, match.begin(0), match[0], boundary)

    boundary
  end

  def guarded?(text, run_start, run, next_index)
    word_before = word_before(text, run_start)
    next_char = text[next_index]

    lowercase_follows?(next_char) ||
      abbreviation?(word_before, run) ||
      single_letter?(word_before, run) ||
      digits_on_both_sides?(word_before, next_char) ||
      url_or_email?(word_before, run)
  end

  def lowercase_follows?(char)
    !char.nil? && char.match?(/\p{Ll}/)
  end

  def abbreviation?(word_before, run)
    return false unless run.start_with?(".")

    ABBREVIATIONS.include?("#{word_tail(word_before)}.".downcase)
  end

  def single_letter?(word_before, run)
    return false unless run.start_with?(".")

    tail = word_tail(word_before)
    tail.length == 1 && tail.match?(/\p{L}/)
  end

  def digits_on_both_sides?(word_before, next_char)
    return false if next_char.nil?

    word_before[-1]&.match?(/\d/) && next_char.match?(/\d/)
  end

  def url_or_email?(word_before, run)
    token = "#{word_before}#{run}"
    token.include?("://") || token.include?("@")
  end

  # The maximal run of non-whitespace characters immediately before the
  # terminator, i.e. the "word" the terminator is attached to.
  def word_before(text, run_start)
    start = run_start
    start -= 1 while start.positive? && !whitespace?(text[start - 1])
    text[start...run_start]
  end

  def word_tail(word_before)
    word_before[WORD_TAIL] || ""
  end

  def skip_whitespace(text, index)
    index += 1 while index < text.length && whitespace?(text[index])
    index
  end

  def whitespace?(char)
    !char.nil? && char.match?(/\s/)
  end
end

TranslationDiff::Segmenters.registry.register(:simple, TranslationDiff::Segmenters::Simple)
