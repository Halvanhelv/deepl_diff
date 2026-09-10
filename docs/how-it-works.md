# How it works

A call to `TranslationDiff.translate` walks a value, cuts the prose in it
into sentences, translates only the sentences no cache already holds, and
puts the value back together in the shape it arrived in.

`TranslationDiff::Translator` coordinates document assembly, provider
resolution, settling the source language, language validation and the
sentence cache. `TranslationDiff::Dispatcher` takes over once there are cache
misses to send: it packs them into batches, throttles each one, makes the
wire call, and fires the `request`, `rate_limit` and `usage` events.
Everything below is a collaborator one of the two drives.

## The steps

1. **The caller's structure is walked, not flattened.**
   `TranslationDiff::Document` visits every leaf `String` of a String, Array
   or deep Hash and can rebuild the same shape from new leaves.
   `TranslationDiff::Leaves` holds the two promises the structure itself does
   not: a nested `nil` comes back as `""`, and the `values` count in an event
   payload is every leaf the caller wrote, translatable or not.

2. **Each leaf becomes a passage of markup and prose.**
   `TranslationDiff::Passage` parses the string with `ox` and records where
   every construct begins, so each run of the source is either markup --
   tags, comments, CDATA, doctypes, processing instructions, `<script>` and
   `<style>` bodies, and anything inside `class="notranslate"` -- or prose.
   Each run becomes a `TranslationDiff::Fragment`, and a fragment is always a
   slice of the source, never a rebuilt string.

3. **Prose is cut into sentences.**
   A prose fragment is split by `config.segmenter` (see [The segmenter
   contract](contracts.md#the-segmenter-contract)) into
   `TranslationDiff::Segment`s. A segment keeps the whitespace it was found
   in: its `#core` is the text a provider sees, with entity references
   decoded to the characters they mean, and its `#render` is markup again.

4. **The cache is consulted once, for every sentence at once.**
   `TranslationDiff::SentenceCache` builds one key per sentence and reads
   them all in a single `read_multi`. Sentences it answers for are already
   done; the rest are misses. See [Caching](caching.md).

5. **The misses are handed to `TranslationDiff::Dispatcher`.**
   `TranslationDiff::Batch.pack` groups them into batches that fit inside the
   provider's declared `max_batch_size` and `max_request_size` -- its
   `TranslationDiff::Capabilities` (see [Providers](providers.md)).
   `Dispatcher` throttles each batch through `config.rate_limiter_instance`
   when one is configured, sends it to the provider, and applies the reply
   back onto the very segments that produced it -- no step ever correlates a
   translation to a sentence by position after the fact.

6. **What came back is written home, and the value is rebuilt.**
   Only sentences that actually got a translation are cached. Then each
   passage renders itself -- markup fragments byte-exact, translated
   sentences re-encoded as HTML text -- and `Document` puts the renders back
   into the caller's shape.

`TranslationDiff::Markup` is the small module underneath steps 2, 3 and 6: it
decodes entity references on the way to a provider, encodes `&` and `<` again
on the way out, and escapes a `<` that opens no tag so `ox` cannot read the
rest of the sentence as markup.

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

A leaf that is not a `String` -- a number, a symbol, `true` -- is handed back
untouched. A nested `nil` comes back as `""`. See
`TranslationDiff::Document` and `TranslationDiff::Leaves` for details.

`to:` is not optional. It defaults to `nil` in the signature and a `nil`
target raises `ArgumentError` naming the keyword, rather than silently
handing your values back untranslated.

## HTML

You can pass HTML as like as plain text:

```ruby
TranslationDiff.translate("<b>Black</b>", from: "en", to: "es")
```
