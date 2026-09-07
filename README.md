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
[`punkt-segmenter`](https://github.com/lfcipriani/punkt-segmenter) to split text
into sentences.

Everything else is duck typed and supplied by you: `TranslationDiff.api` is anything
answering to `#translate`, and both `RedisCacheStore` and `RedisRateLimiter`
take anything answering to `#with`. Bring your own client, pool and store.

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
# `punkt-segmenter`; the API client, the connection pool, and whatever backs
# the cache and the rate limiter are yours to choose and to require.
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

# The largest single request the provider accepts, in characters. Used to
# split long texts into multiple requests.
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

## How it works

- Text nodes are extracted from HTML.
- Every text node is split into sentences (using `punkt-segmenter` gem).
- Cache is checked for the presence of each sentence (using language couple and a hash of string).
- Missing sentences are translated via API and cached.
- Original HTML is recombined from translations and cache data.

*NOTE:* if `:from` is not specified or equal to nil, then the adapter's `#detect` will be called once with a sample of text up to 100 characters long to determine the language, and `#translate` will be called separately with the entire text.
        Try to specify `:from` explicitly to save the extra call.

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
