require "test_helper"

class TokenizerTest < Minitest::Test
  PLAIN_TEXT = "test\nphrase".freeze

  NESTED_NOTRANSLATE = "<span class='notranslate'>foo" \
                       "<span class='notranslate'>bar</span>baz" \
                       "</span>".freeze

  # source => expected tokens
  CASES = {
    "an_empty_source" => [
      "",
      []
    ],
    "markup_holding_nothing_but_a_line_break" => [
      "<div>\n</div>",
      [["<div>", :markup], ["</div>", :markup]]
    ],
    "text_without_markup" => [
      PLAIN_TEXT,
      [[PLAIN_TEXT, :text]]
    ],
    "markup_ending_with_text" => [
      "alfa<span>bravo</span>kilo",
      [
        ["alfa", :text],
        ["<span>", :markup],
        ["bravo", :text],
        ["</span>", :markup],
        ["kilo", :text]
      ]
    ],
    "markup_ending_with_a_tag" => [
      "alfa<span>bravo</span>",
      [
        ["alfa", :text],
        ["<span>", :markup],
        ["bravo", :text],
        ["</span>", :markup]
      ]
    ],
    "non_ascii_text_around_script_and_style" => [
      "аль<span>бра</span>кил<script>js</script><style>b</style>",
      [
        ["аль", :text],
        ["<span>", :markup],
        ["бра", :text],
        ["</span>", :markup],
        ["кил", :text],
        ["<script>js</script><style>b</style>", :markup]
      ]
    ],
    "text_split_into_sentences" => [
      "! Киловольт. <span>Смеркалось.    Ворчало. Кричало.</span>",
      [
        # A lone terminator with no preceding content stays merged: a missed boundary, not a false one.
        ["! Киловольт. ", :text],
        ["<span>", :markup],
        ["Смеркалось.    ", :text],
        ["Ворчало. ", :text],
        ["Кричало.", :text],
        ["</span>", :markup]
      ]
    ],
    "notranslate_spans_kept_as_text" => [
      "<span class='notranslate'>test</span><b>\n<span class='notranslate'>x</span>y</b>",
      [
        ["<span class='notranslate'>test</span>", :text],
        ["<b>", :markup],
        ["\n<span class='notranslate'>x</span>y", :text],
        ["</b>", :markup]
      ]
    ],
    "a_notranslate_span_inside_another_span" => [
      "<span><span class='notranslate'>foo<span>bar<br></span>baz</span></span>",
      [
        ["<span>", :markup],
        ["<span class='notranslate'>foo<span>bar<br></span>baz</span>", :text],
        ["</span>", :markup]
      ]
    ],
    "a_notranslate_span_inside_another_notranslate_span" => [
      NESTED_NOTRANSLATE,
      [[NESTED_NOTRANSLATE, :text]]
    ],
    "a_br_tag_before_a_closing_tag" => [
      "<font size='3'>Смеркалось.<br></font>",
      [
        ["<font size='3'>", :markup],
        ["Смеркалось.", :text],
        ["<br></font>", :markup]
      ]
    ],
    "a_processing_instruction" => [
      "Hey!<br />Look!<?xml:namespace ns=\"urn:office\" ?>",
      [
        ["Hey!", :text],
        ["<br />", :markup],
        ["Look!", :text],
        ["<?xml:namespace ns=\"urn:office\" ?>", :markup]
      ]
    ],
    # Without a handler, the bytes a comment/doctype/CDATA event covers vanish from the rebuilt string.
    "an_html_comment" => [
      "<!-- note --> Visible text.",
      [
        ["<!-- note -->", :markup],
        [" Visible text.", :text]
      ]
    ],
    "a_doctype" => [
      "<!DOCTYPE html><p>Body text.</p>",
      [
        ["<!DOCTYPE html><p>", :markup],
        ["Body text.", :text],
        ["</p>", :markup]
      ]
    ],
    "a_cdata_section" => [
      "Before.<![CDATA[raw & unparsed]]>After.",
      [
        ["Before.", :text],
        ["<![CDATA[raw & unparsed]]>", :markup],
        ["After.", :text]
      ]
    ],
    "a_comment_between_two_sentences" => [
      "First sentence. <!-- aside --> Second sentence.",
      [
        ["First sentence. ", :text],
        ["<!-- aside -->", :markup],
        [" Second sentence.", :text]
      ]
    ],
    "sentences_separated_by_blank_lines" => [
      "Набор «Солнечная механика» от 4М — это 6 экспериментов." \
      "\n\nЮному изобретателю предстоит воочию посмотреть на чудеса.",
      [
        ["Набор «Солнечная механика» от 4М — это 6 экспериментов.\n\n", :text],
        ["Юному изобретателю предстоит воочию посмотреть на чудеса.", :text]
      ]
    ]
  }.freeze

  CASES.each do |name, (source, expected)|
    define_method(:"test_tokenizes_#{name}") do
      assert_equal expected, TranslationDiff::Tokenizer.tokenize(source, segmenter: segmenter)
    end
  end

  private

  # Passed explicitly now that the tokenizer takes its segmenter as a collaborator, not a global.
  def segmenter = TranslationDiff::Segmenters::Pragmatic.new
end
