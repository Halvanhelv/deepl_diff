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
   tags, comments, CDATA, doctypes, processing instructions, the bodies of
   `config.opaque_elements` (`script`, `style`, `pre` and `code` by
   default), and anything inside `class="notranslate"` -- or prose.
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
   Only sentences that actually got a translation are cached, through
   `TranslationDiff::SentenceCache#store` -- see [`write_multi` is
   optional](caching.md#write_multi-is-optional) for what happens when the
   store's write fails partway through a batch. Then each passage renders
   itself -- markup fragments byte-exact, translated sentences re-encoded as
   HTML text -- and `Document` puts the renders back into the caller's
   shape.

`TranslationDiff::Markup` is the small module underneath steps 2, 3 and 6: it
decodes entity references on the way to a provider and, in
`TranslationDiff::Translation::Response.build`, on the way back too, for
every provider -- Google and DeepL both return HTML-escaped text, and
without the second decode a vendor's own `&` was escaped a second time, so
`didn't` came back as `didn&#39;t`. Named entities, and both the decimal
(`&#39;`) and hex (`&#x27;`) numeric forms, are decoded; an entity neither
decoder recognizes, or one that would decode to invalid UTF-8, is left
exactly as it arrived.

Decoding a reply raw would make `&lt;` a bare `<`, and `ox` reads a bare `<`
in front of a letter as an opening tag -- a provider's own `&lt;b attack`
would become a real `<b attack>` element. So a reply is escaped the same way
a source document's own bare angles already are, before it is decoded, and
`Segment#render` re-encodes a translated sentence with
`Markup.encode_translation`: `&` is always escaped, and so is a `<` that is
not shaped like a tag -- a source document's own bare `<` is untouched by
this. **This is a behaviour change:** `if a < b then stop.` used to come
back with the bare `<` exactly as written; it now comes back
`if a &lt; b then stop.`, the correct HTML encoding of that character,
rendering identically in a browser but visible to anything comparing output
byte-for-byte against an earlier release. `>` is left alone -- a stray `>`
never opens anything a parser would honour, so there is nothing to protect
it from.

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

A `<pre>` or `<code>` block is not prose to this gem, so it is left alone.
`config.opaque_elements` names the set treated this way -- `script`,
`style`, `pre` and `code` by default -- and an application can widen or
narrow it. Measured against the live Google API:

```ruby
TranslationDiff.translate(
  "<pre><code>curl -s https://example.com/level | jq '.meters'</code></pre>",
  from: "en", to: "es"
)
# => "<pre><code>curl -s https://example.com/level | jq '.meters'</code></pre>"
```

Before `pre` and `code` joined the opaque set, nothing told the pipeline
that code holds language, not prose: the segmenter cut the block above at
the quote and handed `meters'` to the provider as a sentence of its own,
and Google translated it -- `jq '.meters'` came back as `jq '.metros'`,
inside the quoted filter. Wrap a block you don't want touched in
`class="notranslate"` instead, for protection finer than an element, or for
an element outside `config.opaque_elements`; the providers that honour it
(see [Providers](providers.md)) leave it exactly as written.

**Upgrading:** widening what counts as markup changes what gets sent to the
provider, so it changes cache keys for any document containing a `pre` or
`code` element -- see [Caching](caching.md#what-a-cache-key-is-made-of).
