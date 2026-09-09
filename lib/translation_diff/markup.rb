# Entity references, and a `<` that opens no tag: the two places a document's text is not the text `ox` reports.
module TranslationDiff::Markup
  # Escaping a lone `<` is a workaround around `ox`, not a fix of it: the real fix is our own lexer, and out of scope.

  # A `<` opens a tag only when an element name, a closing name, a declaration or an instruction follows it.
  TAG_OPENER = %r{[A-Za-z!?]|/[A-Za-z]}

  # The two characters escaping has to move: a lone `<`, and an `&` that would read as an escape this module wrote.
  AMBIGUOUS = /&(?=(?:amp;)*lt;)|<(?!#{TAG_OPENER})/

  # `&lt;` was a lone `<`; every further `amp;` is a level the source itself wrote and escaping pushed up by one.
  ESCAPED_ANGLE = /&((?:amp;)*)lt;/

  # The bargain: an untranslated segment renders byte-exact, a translated one renders equivalent HTML, not equal bytes.

  # Named and numeric alike, so nothing an `&` opens survives to be escaped again; `&nbsp;` because Google breaks on it.
  DECODABLE = /&(?:nbsp|amp|lt|gt|quot|apos|#\d+|#[xX]\h+);/

  NBSP = "\u00A0".freeze

  # Only the two characters that are unsafe in HTML text; every other decoded character is left as the character it is.
  ENCODED = { "&" => "&amp;", "<" => "&lt;" }.freeze

  ENCODABLE = /[&<]/

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

  # What a provider is sent is text, so it gets the characters; one left-to-right pass, so nothing is decoded twice.
  def self.decode_entities(text) = text.gsub(DECODABLE) { |entity| decoded(entity) }

  # An entity CGI cannot decode stays as it arrived, and so does a surrogate: that decodes to invalid UTF-8.
  def self.decoded(entity)
    return NBSP if entity == "&nbsp;"

    plain = CGI.unescapeHTML(entity)
    plain.valid_encoding? ? plain : entity
  end

  # What a document renders is markup, so text that changed is made safe again -- and only where it is unsafe.
  def self.encode_entities(text) = text.gsub(ENCODABLE, ENCODED)
end
