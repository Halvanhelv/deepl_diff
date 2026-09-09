require "test_helper"

# Adapted from diasks2/pragmatic_segmenter's Golden Rules (MIT, Copyright (c) 2015 Kevin S. Dias).
class GoldenRulesTest < Minitest::Test
  EXEMPLARS = [
    { language: "en", text: "Hello World. My name is Jonas.",
      expected: ["Hello World.", "My name is Jonas."] },
    { language: "en", text: "My name is Jonas E. Smith.",
      expected: ["My name is Jonas E. Smith."] },
    { language: "ja", text: "これはペンです。それはマーカーです。",
      expected: ["これはペンです。", "それはマーカーです。"] },
    { language: "it", text: "Salve Sig.ra Mengoni! Come sta oggi?",
      expected: ["Salve Sig.ra Mengoni!", "Come sta oggi?"] },
    { language: "ru", text: "Маленькая девочка бежала и кричала: «Не видали маму?».",
      expected: ["Маленькая девочка бежала и кричала: «Не видали маму?»."] },
    { language: "es", text: "¿Cómo está hoy? Espero que muy bien.",
      expected: ["¿Cómo está hoy?", "Espero que muy bien."] },
    { language: "ar",
      text: "سؤال وجواب: ماذا حدث بعد الانتخابات الايرانية؟ طرح الكثير من التساؤلات غداة ظهور نتائج " \
            "الانتخابات الرئاسية الايرانية التي أججت مظاهرات واسعة واعمال عنف بين المحتجين على النتائج " \
            "ورجال الامن. يقول معارضو الرئيس الإيراني إن الطريقة التي اعلنت بها النتائج كانت مثيرة للاستغراب.",
      expected: [
        "سؤال وجواب:",
        "ماذا حدث بعد الانتخابات الايرانية؟",
        "طرح الكثير من التساؤلات غداة ظهور نتائج الانتخابات الرئاسية الايرانية التي أججت مظاهرات واسعة " \
        "واعمال عنف بين المحتجين على النتائج ورجال الامن.",
        "يقول معارضو الرئيس الإيراني إن الطريقة التي اعلنت بها النتائج كانت مثيرة للاستغراب."
      ] },
    { language: "ar",
      # Contains U+202A/U+202C (left-to-right embedding) around the abbreviation's period, a real bidi shape.
      text: "وقال د‪.‬ ديفيد ريدي و الأطباء الذين كانوا يعالجونها في مستشفى برمنجهام إنها كانت " \
            "تعاني من أمراض أخرى. وليس معروفا ما اذا كانت قد توفيت بسبب اصابتها بأنفلونزا الخنازير.",
      expected: [
        "وقال د‪.‬ ديفيد ريدي و الأطباء الذين كانوا يعالجونها في مستشفى برمنجهام إنها كانت " \
        "تعاني من أمراض أخرى.",
        "وليس معروفا ما اذا كانت قد توفيت بسبب اصابتها بأنفلونزا الخنازير."
      ] },
    { language: "el",
      text: "Με συγχωρείτε· πού είναι οι τουαλέτες; Τις Κυριακές δε δούλευε κανένας. " \
            "το κόστος του σπιτιού ήταν £260.950,00.",
      expected: [
        "Με συγχωρείτε· πού είναι οι τουαλέτες;",
        "Τις Κυριακές δε δούλευε κανένας.",
        "το κόστος του σπιτιού ήταν £260.950,00."
      ] },
    { language: "hi",
      text: "सच्चाई यह है कि इसे कोई नहीं जानता। हो सकता है यह फ़्रेन्को के खिलाफ़ कोई विद्रोह रहा हो, " \
            "या फिर बेकाबू हो गया कोई आनंदोत्सव।",
      expected: [
        "सच्चाई यह है कि इसे कोई नहीं जानता।",
        "हो सकता है यह फ़्रेन्को के खिलाफ़ कोई विद्रोह रहा हो, या फिर बेकाबू हो गया कोई आनंदोत्सव।"
      ] },
    { language: "hy", text: "Ի՞նչ ես մտածում: Ոչինչ:",
      expected: ["Ի՞նչ ես մտածում:", "Ոչինչ:"] }
  ].freeze

  def test_pragmatic_the_default_segmenter_matches_the_golden_rules_sample
    segmenter = TranslationDiff::Segmenters::Pragmatic.new

    EXEMPLARS.each do |exemplar|
      actual = sentences_for(segmenter, exemplar[:text], exemplar[:language])
      assert_equal exemplar[:expected], actual, "language: #{exemplar[:language]}, text: #{exemplar[:text].inspect}"
    end
  end

  # Simple isn't held to exact boundaries, but must never corrupt the document while trying.
  def test_simple_still_reconstructs_every_exemplar_even_where_it_under_or_over_splits
    segmenter = TranslationDiff::Segmenters::Simple.new

    EXEMPLARS.each do |exemplar|
      text = exemplar[:text]
      offsets = segmenter.split_offsets(text)
      reconstructed = offsets.each_cons(2).map { |a, b| text[a...b] }.join + text[offsets.last..]

      assert_equal text, reconstructed, "reconstruction failed for #{text.inspect}"
    end
  end

  private

  def sentences_for(segmenter, text, language)
    offsets = segmenter.split_offsets(text, language: language)
    parts = offsets.each_cons(2).map { |a, b| text[a...b] } + [text[offsets.last..]]
    parts.map(&:strip).reject(&:empty?)
  end
end
