# The inputs the pipeline rewrite is judged against. Every one of these is a
# case some earlier bug or review turned up; none is invented.
module PipelineCorpus
  INPUTS = {
    "plain sentence" => "Hello there.",
    "two sentences" => "Hello there. Second sentence!",
    "nested hash" => { title: "One. Two.", body: "Third." },
    "nested array" => ["A. B.", ["C."], "D."],
    "hash with non-strings" => { title: "One.", count: 42, missing: nil, flag: true },
    "empty string" => "",
    "nil" => nil,
    "not a string" => 42,
    "bold markup" => "<b>Bold</b> text here. Second sentence.",
    "attributes preserved" => %(<a href="/x?a=1&b=2" title='q'>Link text.</a> After.),
    "void element" => "One line.<br>Two lines.",
    "unclosed paragraph" => "<p>First para.<p>Second para.",
    "uppercase tags" => "<B>Bold</B> text.",
    "script and style" => "аль<span>бра</span>кил<script>js</script><style>b</style>",
    "processing instruction" => %(Hey!<br />Look!<?xml:namespace ns="urn:office" ?>),
    "comment" => "<!-- internal note --> Visible text here.",
    "doctype" => "<!DOCTYPE html><p>Body text.</p>",
    "cdata" => "Before.<![CDATA[raw & unparsed]]>After.",
    "notranslate span" => %(<span class="notranslate">Bold Mountain</span> is a good place.),
    "nested notranslate" => "<span class='notranslate'>foo<span class='notranslate'>bar</span>baz</span>",
    "notranslate inside span" => "<span><span class='notranslate'>foo<span>bar<br></span>baz</span></span>",
    "br before closing tag" => "<font size='3'>Смеркалось.<br></font>",
    "blank line between sentences" => "Первое предложение.\n\nВторое предложение.",
    "single newline" => "test\nphrase",
    "leading and trailing space" => "  Padded sentence.  ",
    "many sentences" => (1..40).map { |i| "Sentence number #{i}." }.join(" "),
    "non-ascii" => "Привет. Как дела? Всё хорошо.",
    "entity ampersand" => "Salt &amp; pepper. Fine.",
    "entity nbsp" => "Hard&nbsp;space here. Fine.",
    "bare less-than" => "if a < b then stop. Fine.",
    "bare less-than and greater" => "5 < 6 and 7 > 6. True."
  }.freeze

  # Written BEFORE the rewrite, on purpose. A list assembled after seeing the
  # new output would be a report of what happened, not a prediction that can
  # fail. Everything not named here must come out byte-identical.
  #
  # Both entries change because the rewrite fixes them: today the entity
  # reaches the provider raw, and everything after a bare "<" is treated as
  # markup and never translated at all.
  EXPECTED_TO_CHANGE = [
    "entity ampersand",
    "entity nbsp",
    "bare less-than",
    "bare less-than and greater"
  ].freeze
end
