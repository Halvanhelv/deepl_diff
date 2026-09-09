# Entity references, and a `<` that opens no tag: the two places a document's text is not the text `ox` reports.
module TranslationDiff::Markup
  # Escaping a lone `<` is a workaround around `ox`, not a fix of it: the real fix is our own lexer, and out of scope.

  # A `<` opens a tag only when an element name, a closing name, a declaration or an instruction follows it.
  TAG_OPENER = %r{[A-Za-z!?]|/[A-Za-z]}

  # The two characters escaping has to move: a lone `<`, and an `&` that would read as an escape this module wrote.
  AMBIGUOUS = /&(?=(?:amp;)*lt;)|<(?!#{TAG_OPENER})/

  # `&lt;` was a lone `<`; every further `amp;` is a level the source itself wrote and escaping pushed up by one.
  ESCAPED_ANGLE = /&((?:amp;)*)lt;/

  # `&amp;` and `&nbsp;` reach Google raw today and it stops translating at them; `&lt;` is this module's own escape.
  DECODED = { "&amp;" => "&", "&lt;" => "<", "&nbsp;" => "\u00A0" }.freeze

  DECODABLE = /&(?:amp|lt|nbsp);/

  # `<` is missing on purpose: restoring a lone angle is the escape's job, and a real tag in prose must stay a tag.
  ENCODED = { "&" => "&amp;", "\u00A0" => "&nbsp;" }.freeze

  ENCODABLE = /[&\u00A0]/

  # Hands back markup `ox` can parse: same document, with every lone `<` written as the entity it should have been.
  def self.escape_bare_angles(source)
    source.gsub(AMBIGUOUS) { |ambiguous| ambiguous == "&" ? "&amp;" : "&lt;" }
  end

  # The exact inverse: one `amp;` off every escaped angle, and the angles with none left were the lone ones.
  def self.restore_bare_angles(rendered)
    rendered.gsub(ESCAPED_ANGLE) do
      levels = Regexp.last_match(1)
      levels.empty? ? "<" : "&#{levels.delete_prefix('amp;')}lt;"
    end
  end

  # What a provider is sent is text, so it gets the characters; a document arriving without entities gains none.
  def self.decode_entities(text) = text.gsub(DECODABLE, DECODED)

  # What a document renders is markup, so a decoded character goes back to its entity -- a lone `&` gains one.
  def self.encode_entities(text) = text.gsub(ENCODABLE, ENCODED)
end
