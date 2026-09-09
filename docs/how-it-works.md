# How it works

- Text nodes are extracted from HTML.
- Every text node is split into sentences by `config.segmenter` (see
  [The segmenter contract](contracts.md#the-segmenter-contract)).
- Cache is checked for the presence of each sentence (using language couple and a hash of string).
- Missing sentences are translated via the provider and cached.
- Original HTML is recombined from translations and cache data.

*NOTE:* if `:from` is not specified or equal to nil, then the provider's `#detect` will be called once with a sample of text up to 100 characters long to determine the language, and `#translate` will be called separately with the entire text.
        Try to specify `:from` explicitly to save the extra call -- it also improves segmentation, since the segmenter only sees a language when `:from` is given (see [The segmenter contract](contracts.md#the-segmenter-contract)).

## Input

`TranslationDiff.translate` can receive string, array or deep hash and will return the same, but translated.

```ruby
TranslationDiff.translate("test", from: "en", to: "es")
TranslationDiff.translate(%w[test language], from: "en", to: "es")
TranslationDiff.translate(
  { title: "test", values: { type: "frequent" } }, from: "en", to: "es"
)
```

See `TranslationDiff::Linearizer` for details.

## HTML

You can pass HTML as like as plain text:

```ruby
TranslationDiff.translate("<b>Black</b>", from: "en", to: "es")
```
