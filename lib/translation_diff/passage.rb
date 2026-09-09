# A source document as markup and prose: the markup kept as found, the prose cut into segments a provider can take.
class TranslationDiff::Passage
  attr_reader :fragments

  # The source is scanned with every lone `<` escaped, so the offsets, the slices and the render all agree on it.
  def initialize(source, segmenter:, language: nil)
    @source = TranslationDiff::Markup.escape_bare_angles(source)
    @segmenter = segmenter
    @language = language
    @fragments = Scanner.new(@source).runs.map { |run| fragment(run) }
  end

  # The translatable sentences, in document order; the empty ones are whitespace a provider has no use for.
  def segments = fragments.flat_map(&:segments)

  # Entities are a segment's business, so the only thing left to undo here is the escape this class put in.
  def render
    TranslationDiff::Markup.restore_bare_angles(fragments.map(&:render).join)
  end

  private

  # Every fragment is a slice of the source, never a rebuilt string; that is what makes an untranslated render exact.
  def fragment(run)
    from, to, prose = run
    slice = @source.byteslice(from, to - from)
    return TranslationDiff::Fragment.markup(slice) unless prose

    TranslationDiff::Fragment.prose(slice, segmenter: @segmenter, language: @language)
  end

  # Ox reports a byte position for every construct it sees; recording those is what lets rendering slice the source.
  class Scanner < Ox::Sax
    # Content nobody wants translated, however much of it looks like prose.
    OPAQUE = %i[script style].freeze

    # Providers honour this class themselves under the HTML mode this gem sends, so the element must reach them whole.
    PROTECTED = "notranslate".freeze

    OPENING_ANGLE = "<".ord

    # Where a run begins and whether it is prose; prose is set after the fact when an element claims protection.
    Mark = Struct.new(:offset, :prose)

    # Ox reports positions only to a handler that already has the ivar, so @pos exists before parsing starts.
    def initialize(source)
      super()
      @source = source
      @pos = 0
      @marks = []
      @protected_depth = 0
      @opaque_depth = 0
      @pending = nil
    end

    # Triples of [first byte, last byte + 1, prose?], contiguous, covering the source exactly once.
    def runs
      Ox.sax_html(self, StringIO.new(@source))
      merge(bounds)
    end

    # Protection beats opacity on purpose: a caller wrapping a subtree asked for it to be passed through as it is.
    def start_element(name)
      return @protected_depth += 1 if @protected_depth.positive?

      @opaque_depth += 1 if @opaque_depth.positive? || OPAQUE.include?(name)
      @pending = mark(prose: false)
    end

    # Attributes arrive straight after their own start element, so @pending is that element and never another.
    def attr(name, value)
      return unless @pending && protection?(name, value)

      @pending.prose = true
      @protected_depth = 1
      @pending = nil
    end

    def end_element(_name)
      return @protected_depth -= 1 if @protected_depth.positive?

      @opaque_depth -= 1 if @opaque_depth.positive?
      record(prose: false)
    end

    def value(_value) = record(prose: @opaque_depth.zero?)

    def comment(_content) = record(prose: false)

    def cdata(_content) = record(prose: false)

    def doctype(_content) = record(prose: false)

    def instruct(_target) = record(prose: false)

    private

    # Ox lowercases element names but not attribute names; the value stays exact because HTML class tokens are.
    def protection?(name, value)
      name.to_s.casecmp?("class") && value.split.include?(PROTECTED)
    end

    # Everything inside a protected element belongs to the run that element opened, so it records nothing of its own.
    def record(prose:)
      @pending = nil
      return if @protected_depth.positive?

      mark(prose: prose)
    end

    # Ox counts from one. A markup mark that does not land on a "<" is a tag Ox implied, not one the source holds.
    def mark(prose:)
      offset = @pos - 1
      return nil if offset.negative? || (!prose && @source.getbyte(offset) != OPENING_ANGLE)

      Mark.new(offset, prose).tap { |recorded| @marks << recorded }
    end

    # Each mark owns the source as far as the next one begins, and the last one owns whatever is left.
    def bounds
      marks = ordered
      finishes = marks.drop(1).map(&:offset) << @source.bytesize
      marks.zip(finishes).map { |mark, finish| [mark.offset, finish, mark.prose] }
    end

    # Ox skips the whitespace ahead of the first construct it reports, so a prose run is seeded where it starts.
    def ordered
      sorted = @marks.sort_by.with_index { |mark, index| [mark.offset, index] }
      return sorted if sorted.first&.offset&.zero?

      sorted.unshift(Mark.new(0, true))
    end

    # Adjacent prose has to become one run, or a notranslate element would be cut off from the sentence it sits in.
    def merge(spans)
      spans.reject { |from, to, _prose| from == to }
           .chunk_while { |before, after| before.last == after.last }
           .map { |chunk| [chunk.first[0], chunk.last[1], chunk.first[2]] }
    end
  end
end
