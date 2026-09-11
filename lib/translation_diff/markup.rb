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

  # Named and numeric alike, so nothing an `&` opens survives to be escaped again and rendered as its own spelling.
  DECODABLE = /&(?:[A-Za-z][A-Za-z0-9]*|#\d+|#[xX]\h+);/

  # Which of the two decoders an entity belongs to: Ox knows every HTML5 name, CGI knows both numeric forms.
  NAMED = /\A&([A-Za-z][A-Za-z0-9]*);\z/

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

  # An entity neither decoder knows stays as it arrived, and so does a surrogate: that decodes to invalid UTF-8.
  def self.decoded(entity)
    name = entity[NAMED, 1]
    plain = name ? named(name) : CGI.unescapeHTML(entity)
    plain.valid_encoding? ? plain : entity
  end

  # A document repeats the same handful of names, and only a name that resolved is kept, so the table cannot be grown.
  def self.named(name) = resolved[name] || resolve(name)

  def self.resolved = @resolved ||= {}

  # One well-formed entity alone in an element is the only input Ox decodes safely -- prose with a lone `&` raises.
  def self.resolve(name)
    entity = "&#{name};"
    resolver = Resolver.new
    Ox.sax_html(resolver, StringIO.new("<e>#{entity}</e>"))
    return entity if resolver.text.nil? || resolver.text == entity

    resolved[name] = resolver.text
  rescue StandardError
    entity
  end

  # What a document renders is markup, so text that changed is made safe again -- and only where it is unsafe.
  def self.encode_entities(text) = text.gsub(ENCODABLE, ENCODED)

  # An entity the round trip already produced must not be escaped a second time, and a `<` shaped like a tag is
  # trusted the same way a source tag already is -- everything else a provider sent back is untrusted new text.
  TRANSLATED_ENCODABLE = /&(?:amp|lt|gt);|&|<(?!#{TAG_OPENER})/

  # What a translation renders as: unlike #encode_entities, this leaves a provider's own reproduced tags alone.
  def self.encode_translation(text)
    text.gsub(TRANSLATED_ENCODABLE) { |match| match.length == 1 ? ENCODED[match] : match }
  end

  # Ox hands back the decoded text of the one element it was given; a name it does not know arrives as the text it was.
  class Resolver < Ox::Sax
    attr_reader :text

    def value(value) = @text = value.as_s
  end
end
