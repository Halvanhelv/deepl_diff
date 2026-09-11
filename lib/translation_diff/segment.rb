# A sentence with the whitespace it was found in: its core is the text a provider sees, its render is markup again.
class TranslationDiff::Segment
  attr_reader :source, :body, :core
  attr_accessor :translation

  # A core is compared decoded, so a sentence that was only `&nbsp;` counts as the padding it is and is never sent.
  BLANK = /\A[[:space:]]*\z/

  def initialize(source)
    @source = source.dup
    @leading, @body, @trailing = @source.partition(/[^[:space:]].*[^[:space:]]|[^[:space:]]/m)
    @core = TranslationDiff::Markup.decode_entities(@body)
  end

  # Reflects whether a translation is set right now, not history -- clearing it to nil flips this back to false.
  def translated? = !translation.nil?

  def empty? = core.match?(BLANK)

  # Untranslated hands back the bytes it was cut from; a translation is text, so it is encoded as markup on the way out.
  def render
    "#{@leading}#{translated? ? escaped_translation : @body}#{@trailing}"
  end

  private

  # @body already carries this same escape from Passage; without it, Passage's one shared restore pass would
  # read a translated `&lt;` as a source document's own bare `<` and hand back markup nobody asked for.
  def escaped_translation
    TranslationDiff::Markup.escape_bare_angles(TranslationDiff::Markup.encode_translation(translation))
  end
end
