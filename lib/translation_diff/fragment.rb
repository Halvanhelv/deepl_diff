# A run of the source that is either markup, handed back as found, or prose, handed back through its segments.
class TranslationDiff::Fragment
  EMPTY = [].freeze

  attr_reader :source

  # Markup has nothing a provider should see, so it carries no segments and renders the bytes it was cut from.
  def self.markup(source) = new(source, nil)

  # Prose is cut where the segmenter says sentences begin, so every segment keeps the whitespace it was found in.
  def self.prose(source, segmenter:, language: nil)
    new(source, cut(source, segmenter.split_offsets(source, language: language)))
  end

  # The offsets start at 0 and strictly increase, so slicing between them and from the last to the end is exact.
  def self.cut(source, offsets)
    sentences = offsets.each_cons(2).map { |from, to| source[from...to] } << source[offsets.last..]
    sentences.map { |sentence| TranslationDiff::Segment.new(sentence) }
  end
  private_class_method :cut

  def initialize(source, segments)
    @source = source
    @segments = segments
  end

  def markup? = @segments.nil?

  def segments = @segments || EMPTY

  def render = markup? ? source : @segments.map(&:render).join
end
