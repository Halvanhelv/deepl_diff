class TranslationDiff::Tokenizer < Ox::Sax
  SKIP = %i[script style].freeze
  INNER_SPANS = %i[notranslate span end_span end_notranslate].freeze
  HTML_OPTIONS = { smart: true, skip: :skip_none }.freeze

  # Ox::Sax provides no initializer to chain to.
  # rubocop:disable-next Lint/MissingSuper
  def initialize(source, segmenter:, language: nil)
    @pos = nil
    @source = source
    @segmenter = segmenter
    @language = language
    @tokens = nil
    @context = []
    @sequence = []
    @indicies = []
  end

  def instruct(target)
    start_markup(target)
  end

  def end_instruct(target)
    end_markup(target)
  end

  def start_element(name)
    start_markup(name)
  end

  # Without a handler here, a mid-sentence comment leaks "<!" and hands its own contents to the provider as prose.
  def comment(_value) = mark_markup
  def doctype(_value) = mark_markup
  def cdata(_value) = mark_markup

  def end_element(name)
    end_markup(name)
  end

  def attr(name, value)
    return unless @context.last == :span
    return unless name == :class && value == "notranslate"
    return if notranslate?

    @sequence[-1] = :notranslate
  end

  def text(value)
    return if value == ""

    @sequence << (SKIP.include?(@context.last) ? :markup : :text)
    @indicies << (@pos - 1)
  end

  def tokens
    @tokens ||= token_sequences_joined
                .tap { |tokens| make_sentences_from_last_token(tokens) }
  end

  private

  def token_sequences_joined
    raw_tokens.each_with_object([]) do |token, tokens|
      if tokens.empty? # Initial state
        tokens << token
      elsif tokens.last[1] == token[1]
        # Join series of tokens of the same type into one
        tokens.last[0].concat(token[0])
      else
        # If token before :markup is :text we need to split it into sentences
        make_sentences_from_last_token(tokens)
        tokens << token
      end
    end
  end

  def make_sentences_from_last_token(tokens)
    return if tokens.empty?

    tokens.concat(sentences(tokens.pop[0])) if tokens.last[1] == :text
  end

  def sentences(value)
    return [] if value.strip.empty?

    offsets = @segmenter.split_offsets(value, language: @language)
    return [[value, :text]] if offsets.size == 1

    offsets.each_cons(2).map { |left, right| [value[left...right], :text] } +
      [[value[offsets.last..], :text]]
  end

  # Whether the sequence is between `:notranslate` and `:end_notranslate`
  def notranslate?
    @sequence.select { |item| item[/notranslate/] }.last == :notranslate
  end

  # Returns the item for last opened span
  def end_span
    return :markup unless notranslate?

    opened_spans = @sequence
                   .reverse
                   .take_while { |item| item != :notranslate }
                   .map { |item| { span: 1, end_span: -1 }.fetch(item, 0) }
                   .reduce(0, :+)

    opened_spans.positive? ? :end_span : :end_notranslate
  end

  def raw_tokens
    @raw_tokens ||= @indicies.map.with_index do |i, n|
      first = i
      last = (@indicies[n + 1] || 0) - 1
      value = fix_utf(@source.byteslice(first..last))
      type = @sequence[n]
      type = :text if INNER_SPANS.include?(type)
      [value, type]
    end
  end

  def fix_utf(value)
    value.encode("UTF-8", undef: :replace, invalid: :replace, replace: " ")
  end

  # Inside a notranslate region this becomes :text: the whole region is handed to the provider as one unit.
  def mark_markup
    @sequence << (notranslate? ? :text : :markup)
    @indicies << (@pos - 1)
  end

  def start_markup(name)
    @context << name
    @sequence << (if notranslate?
                    name == :span ? :span : :text
                  else
                    :markup
                  end)
    @indicies << (@pos - 1)
  end

  def end_markup(name)
    @context.pop
    @sequence << (if notranslate?
                    name == :span ? end_span : :text
                  else
                    :markup
                  end)
    @indicies << (@pos - 1) unless @pos == @source.bytesize
  end

  class << self
    def tokenize(value, segmenter:, language: nil)
      # Anything that is not a string has no markup and no sentences in it.
      return [] unless value.is_a?(String)

      tokenizer = new(value, segmenter: segmenter, language: language).tap do |h|
        Ox.sax_parse(h, StringIO.new(value), HTML_OPTIONS)
      end
      tokenizer.tokens
    end
  end
end
