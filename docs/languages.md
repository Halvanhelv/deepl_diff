# Languages

`TranslationDiff::Languages` answers, without making a request, whether a
provider translates a given source into a given target. `Translator` calls it
before every translation and refuses a pair it says no to.

```ruby
TranslationDiff::Languages.supports?(:deepl, from: "en", to: "ru")   # => true
TranslationDiff::Languages.supports?(:amazon, from: "en", to: "ru")  # => nil
```

Three answers, not two: `true`, `false`, and `nil` for "no opinion". `nil` is
not a refusal -- a provider this registry knows nothing about is never
blocked from translating anything.

## What ships

One JSON file per provider under `data/languages/`, each naming the date it
was captured and the endpoint it came from:

```json
{
  "provider": "deepl",
  "captured_at": "2026-09-10",
  "endpoint": "https://api.deepl.com/v2/languages",
  "source": ["ar", "bg", "cs", "..."],
  "target": ["ar", "bg", "cs", "en-gb", "en-us", "..."]
}
```

`captured_at` is not decoration: it is the difference between "these are the
languages" and "these were the languages on 10 September 2026", and only the
second is true.

Data ships for **DeepL, Google, Azure and ModernMT** only. **Amazon** ships
none -- its language list needs signed credentials, so nothing can be fetched
without them. **LibreTranslate** ships none either, for a different reason:
it is self-hosted, so the language set belongs to whichever instance you
point this gem at, not to a vendor this gem can capture once and ship.

A provider with no shipped data -- Amazon, LibreTranslate, or any provider of
your own -- refuses nothing. `Languages.supports?` returns `nil` for it,
every time, and `Translator` treats `nil` the same as `true`.

## Matching a code

A code is matched downcased, on its primary subtag, so `en-GB` and `en`
match each other in both directions.

This is deliberately permissive. The registry exists to catch a wrong
language -- `to: "klingon"`, a swapped pair, a typo -- not to adjudicate a
wrong regional variant. `Languages.supports?(:azure, from: "en", to: "zh")`
answers `true`, even though Azure itself wants `zh-Hans` or `zh-Hant` as a
target and would reject a bare `zh`. The rule can over-allow; it must never
wrongly refuse a pair the provider would actually have accepted.

One more rule, for a mismatch the vendors themselves create. ModernMT
publishes ISO 639-3 individual codes where applications write the ISO 639-1
macrolanguage: it lists `pes`, not `fa`, and `uzn`, not `uz`. A vendor that
translates the individual language translates the macrolanguage it belongs
to, so `to: "fa"` is accepted against a list carrying `pes`.

That holds in one direction only. A vendor publishing `zh` has not promised
to accept `cmn`, so `Languages.supports?(:deepl, from: "en", to: "cmn")`
answers `false` -- DeepL would reject the code it was sent.

## The two escapes

Shipped data goes stale, and a vendor adding a language must not make this
gem refuse work that would now succeed. Two escapes exist for that:

```ruby
# Per call
TranslationDiff.translate(text, from: "en", to: "yue", assume_supported: true)

# Globally
TranslationDiff.configure { |config| config.validate_languages = false }
```

`assume_supported:` is a reserved keyword, like `provider:` and `config:` --
it is read by `Translator` and never forwarded to the provider itself.

## `rake languages:refresh`

A maintainer's tool, not something an application runs: it re-fetches every
provider's language lists from its vendor and rewrites the shipped files,
which is why it needs each vendor's own credentials configured to do
anything.

A provider whose fetch fails keeps its previous file -- an emptied list from
a timed-out request would be worse than a stale one -- and the task reports
which providers failed and why, rather than failing silently. Its output is
meant to be reviewed as a diff, the way any change to shipped data should be,
before it is committed.
