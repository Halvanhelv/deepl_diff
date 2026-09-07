# TranslationDiff

A translation wrapper that helps to translate only changes between revisions of
long texts. It ships with a DeepL adapter, but any translation provider can be
used by implementing a small adapter contract -- this gem has no hard
dependency on DeepL or any other provider.

**TranslationDiff** based on [GoogleTranslateDiff](https://github.com/gzigzigzeo/google_translate_diff)
## Use case

Assume your project contains a significant amount of products descriptions which:
- Require retranslation each time user edits them.
- Have a lot of equal parts (like return policy).
- Change frequently.

If your user changes a single word within the long description, you will be charged for the retranslation of the whole text.

Much better approach is to try to translate every repeated structural element (sentence) in your texts array just once to save money. This gem helps to make it done.

## Dependencies

This gem loads two: [`ox`](https://github.com/ohler55/ox) to walk the HTML, and
[`pragmatic_segmenter`](https://github.com/diasks2/pragmatic_segmenter), which backs
the default sentence segmenter and has zero dependencies of its own. See [Segmenters
and the segmenter contract](#segmenters-and-the-segmenter-contract) below if you want
to avoid the second dependency.

Everything else is duck typed and supplied by you: `TranslationDiff.api` must satisfy
the five-method adapter contract described in [Adapters and the adapter
contract](#adapters-and-the-adapter-contract) below -- not just `#translate` -- and both
`RedisCacheStore` and `RedisRateLimiter` take anything answering to `#with`. Bring your
own client, pool and store.

## Installation

Add this line to your application's Gemfile:

```ruby
gem 'translation_diff'
```

And then execute:

    $ bundle

Or install it yourself as:

    $ gem install translation_diff

## Usage

```ruby
require "translation_diff"

# None of these are dependencies of this gem. It loads only `ox` and
# `pragmatic_segmenter`; the API client, the connection pool, and whatever
# backs the cache and the rate limiter are yours to choose and to require.
require "deepl"
require "redis"
require "connection_pool"
require "redis-namespace"
require "ratelimit" # Optional, only if you use the rate limiter

DeepL.configure do |config|
  config.auth_key = "your-api-token"
end

pool = ConnectionPool.new(size: 10, timeout: 5) { Redis.new }

TranslationDiff.api = TranslationDiff::Adapters::DeepL.new(DeepL)
TranslationDiff.cache_store =
  TranslationDiff::RedisCacheStore.new(pool, timeout: 604_800, namespace: "t")

# Optional
TranslationDiff.rate_limiter =
  TranslationDiff::RedisRateLimiter.new(pool, threshold: 8000, interval: 60, namespace: "t")

TranslationDiff.translate("test translations", from: "en", to: "es")
```

## Adapters and the adapter contract

`TranslationDiff.api` can be any object that satisfies the following contract.
`TranslationDiff::Adapters::DeepL` is the adapter shown above, wrapping the
[`deepl-rb`](https://github.com/wikiti/deepl-rb) gem; `TranslationDiff::Adapters::Null`
is a second, trivial adapter useful for tests and for wiring up a pipeline
before a real provider is available. Neither the DeepL client nor any other
provider's SDK is a dependency of this gem -- write your own adapter around
whatever translation API you use, and assign it to `TranslationDiff.api`.

An adapter must implement:

```ruby
# Translates an array of strings and returns an array of strings, one per
# input, in the same order. Provider-specific options (e.g. `formality:`)
# arrive through **options and are passed straight through to the provider.
def translate(texts, from:, to:, **options)

# Detects the source language of a single string and returns it. Optional:
# omit this method entirely if the provider has no detection endpoint, or if
# callers of this gem always pass `from:` explicitly. When `detect` is
# missing and `from:` is not given, TranslationDiff raises rather than
# guessing.
def detect(text)

# The largest single request the provider accepts, in characters of the
# escaped form -- which is what the chunker measures (CGI.escape(text).size,
# not String#size). For Cyrillic and other non-Latin text this is 6 to 9
# times the raw character count. Declaring the provider's raw character
# limit here will either waste most of the budget (if you under-report) or
# raise Chunker::Error on text the provider would actually have accepted
# (if you over-report). Used to split long texts into multiple requests.
def max_request_size

# The largest number of strings the provider accepts in one batched request.
# Used to split large arrays into multiple requests.
def max_batch_size

# A short, stable, non-empty string identifying this provider. Used to
# namespace cache keys, so that switching providers does not return one
# provider's cached translations for another.
def cache_key
```

`test/support/adapter_contract.rb` is the executable form of this contract:
include `AdapterContract` in a test class that defines `#adapter`, and it
verifies `translate`, `max_request_size`, `max_batch_size` and `cache_key`
behave as documented above.

*Former name:* this gem was published as `deepl_diff` before version 3.0.0.
`deepl_diff` is deprecated in favor of `translation_diff`, which is
functionally the same gem under a name that no longer implies a dependency on
DeepL specifically.

**Upgrading from `deepl_diff`:** every cache key changed in 3.0.0 -- the provider,
the provider options and normalised language codes are now part of the key.
Nothing cached by `deepl_diff` is reused; the next translation of every sentence is
a cache miss, once, everywhere. See [CHANGELOG.md](CHANGELOG.md) for the full list
of breaking changes.

## Segmenters and the segmenter contract

`TranslationDiff.segmenter` decides where a text node is cut into sentence-sized
cache units, the same way `TranslationDiff.api` decides how a sentence gets
translated. It defaults to `TranslationDiff::Segmenters::Pragmatic.new` and can be
swapped for any object implementing:

```ruby
# Returns the offsets at which a new sentence begins, always starting with 0
# and strictly increasing. Slicing the source between consecutive offsets, and
# from the last offset to the end, reconstructs the source exactly -- a wrong
# boundary never corrupts the document, it only changes how the text is
# grouped into cache units.
#
# language: is an ISO 639-1 code such as "en" or "ru" when the caller already
# knows the source language, and nil when it does not -- see below.
def split_offsets(text, language: nil)
```

Two segmenters ship with this gem:

- **`TranslationDiff::Segmenters::Pragmatic`** (the default) wraps the
  [`pragmatic_segmenter`](https://github.com/diasks2/pragmatic_segmenter) gem,
  which ships per-language rule sets rather than one rule set applied to every
  script. Measured against a sample of the Golden Rules corpus, the de-facto
  benchmark for sentence segmentation (see
  `test/translation_diff/golden_rules_test.rb`), it scores 75/80 against
  `Simple`'s 47/80, and the gap is largest on languages that have no letter
  case at all -- Arabic, Hindi, Armenian, Greek -- which `Simple` cannot
  reason about by design.

  Before segmenting, `Pragmatic` replaces every single newline (one with no
  adjoining newline) with a space in a shadow copy of the text, segments the
  shadow, and slices the *original* text at the recovered offsets --
  `pragmatic_segmenter` otherwise treats almost any single newline as a
  sentence boundary candidate even with no punctuation at all, which is a
  false split (the harmful kind) on the incidental newlines that HTML text
  nodes routinely carry from source formatting. A run of two or more
  newlines (a real paragraph break) is left alone. This costs one Golden
  Rules point (76 -> 75): one exemplar shaped like a bare list of items
  separated by single newlines, with no punctuation, now segments as one
  unit instead of three. That shape does not arise in this gem's actual
  input -- HTML list items are separated by markup into distinct text nodes
  already -- so the point is a deliberate trade, not a regression to chase.

  Language codes are normalised before reaching `pragmatic_segmenter`:
  downcased, with any region subtag after `-` or `_` dropped, and checked
  against the codes `pragmatic_segmenter` actually has rules for, falling
  back to English otherwise. DeepL -- this gem's own flagship adapter --
  sends codes exactly like `"RU"` and `"EN-GB"`; without normalising,
  `pragmatic_segmenter`'s own lookup is case-sensitive and region-blind, so
  those would silently miss their rule set entirely.
- **`TranslationDiff::Segmenters::Simple`** is a zero-dependency, in-house
  segmenter. It splits conservatively on punctuation followed by whitespace,
  guarded by a handful of signals (a known abbreviation, an initial, digits on
  both sides, a URL or email, or a lowercase letter immediately following --
  the guard that gives it away as built for cased scripts). Reach for it if
  you want no extra dependency and you only ever translate from languages
  written in a cased script (Latin, Cyrillic, Greek's own script aside,
  Armenian, and similar).

Passing `from:` to `::translate` does more than skip a detection call (see
[How it works](#how-it-works) below): it is also the only way a segmenter sees
the source language. When `from:` is omitted, the language is genuinely
unknown at the time the text is segmented -- language detection needs the
segmented text to build its sample, so segmentation cannot wait for it -- and
`Pragmatic` falls back to English rules, which can mis-segment other
languages (Russian abbreviations, for one). `Simple` ignores the argument
entirely; its rules are language-neutral.

`pragmatic_segmenter`'s cleaner rewrites the sentences it hands back in ways
shadowing does not cover -- it collapses runs of three or more spaces, and it
respaces abbreviations like `"Ph.D."` into `"Ph. D."`, among other things --
so the sentence `Pragmatic` gets back does not always appear verbatim in the
source any more. `Pragmatic` never guesses at an offset it cannot verify: it
walks the returned sentences in order, keeps every offset it locates, and
stops at the first one it cannot. The unrecoverable remainder of the text
then stands as one final unit instead of being sliced further. This is a
*coarsening*, not a failure -- the text still translates correctly, the cache
unit is just larger than it could have been -- and it is silent by design,
the same way a segmenter simply not splitting a node has always been
acceptable. `TranslationDiff::Segmenters::Pragmatic::Error` (a
`TranslationDiff::Error`) still exists and is still raised, but only if
`Pragmatic` itself computes offsets that violate its own postcondition
(starting at 0, strictly increasing, all within the text) -- not by ordinary
use of `pragmatic_segmenter`, however it rewrites a sentence.

## Errors

Every error this gem raises inherits from `TranslationDiff::Error < StandardError`,
so rescuing the gem's failures in one clause is a single `rescue TranslationDiff::Error`:

```
TranslationDiff::Error
├── TranslationDiff::Request::Error        # e.g. api/cache_store not configured,
│                                           # adapter returned the wrong number of
│                                           # translations, from: missing and the
│                                           # adapter cannot detect
├── TranslationDiff::Cache::Error          # provider options have no stable
│                                           # serialisation for the cache key
├── TranslationDiff::Chunker::Error        # a single value is larger than the
│                                           # adapter's max_request_size
├── TranslationDiff::Segmenters::Pragmatic::Error
│                                           # Pragmatic computed offsets that
│                                           # violate its own postcondition --
│                                           # not raised by ordinary use
└── TranslationDiff::RedisRateLimiter::RateLimitExceeded
```

## How it works

- Text nodes are extracted from HTML.
- Every text node is split into sentences by `TranslationDiff.segmenter` (see
  [Segmenters and the segmenter contract](#segmenters-and-the-segmenter-contract)).
- Cache is checked for the presence of each sentence (using language couple and a hash of string).
- Missing sentences are translated via API and cached.
- Original HTML is recombined from translations and cache data.

*NOTE:* if `:from` is not specified or equal to nil, then the adapter's `#detect` will be called once with a sample of text up to 100 characters long to determine the language, and `#translate` will be called separately with the entire text.
        Try to specify `:from` explicitly to save the extra call -- it also improves segmentation, since the segmenter only sees a language when `:from` is given (see [Segmenters and the segmenter contract](#segmenters-and-the-segmenter-contract)).

## Input

`::translate` can receive string, array or deep hash and will return the same, but translated.

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

## Very long texts

Every provider limits how large a single request or a single batch can be.
Adapters state their own limits through `#max_request_size` and
`#max_batch_size`; if your text is longer than that, TranslationDiff splits it
into multiple requests automatically. The DeepL adapter, for example, caps
requests at 1700 characters and batches at 300 sentences.

## Development

After checking out the repo, run `bin/setup` to install dependencies. Then, run `rake test` to run the tests. You can also run `bin/console` for an interactive prompt that will allow you to experiment.

To install this gem onto your local machine, run `bundle exec rake install`. To release a new version, update the version number in `version.rb`, and then run `bundle exec rake release`, which will create a git tag for the version, push git commits and tags, and push the `.gem` file to [rubygems.org](https://rubygems.org).

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/Halvanhelv/translation_diff.
