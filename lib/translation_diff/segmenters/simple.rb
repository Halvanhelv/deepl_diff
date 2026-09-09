# frozen_string_literal: true

# No runtime dependency, but deliberately conservative: every guard exists to turn a split off, never on.
class TranslationDiff::Segmenters::Simple
  # CJK terminators need no trailing whitespace and no guards -- those scripts have no case or abbreviations.
  TERMINATOR = /[.!?…]+|[。！？]+/

  CJK_TERMINATOR = /\A[。！？]/

  # Words that end in "." without ending a sentence, matched case-insensitively; extend for your own domain.
  ABBREVIATIONS = %w[
    т.е. т.д. т.п. см. рис. стр. гр. ул. г. руб. проф. акад. тыс. млн. млрд. им.
    Mr. Mrs. Ms. Dr. Prof. St. etc. e.g. i.e. vs. approx. No. im. fig. Fig. vol. p. pp.
  ].map(&:downcase).freeze

  # Strips leading punctuation like an opening quote so `"Dr. Smith` still guards on "Dr.".
  WORD_TAIL = /[\p{L}\p{N}.]+\z/

  def self.build(_config) = new

  # language: is part of the shared segmenter contract but ignored here -- these rules are language-neutral.
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

  # If whitespace follows, it's attached to the sentence that just ended, not left as a leading gap.
  def cjk_boundary(text, run_end)
    boundary = skip_whitespace(text, run_end)
    boundary if boundary < text.length
  end

  # A bare "." with nothing after it is not a sentence break, it is a string that stops mid-thought.
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

  # The maximal run of non-whitespace characters immediately before the terminator.
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
