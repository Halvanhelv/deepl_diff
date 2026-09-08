# TranslationDiff

A translation cache that helps translate only changes between revisions of
long texts. It ships with DeepL and Google Cloud Translation providers, but
any translation service can be plugged in by implementing a small provider
contract -- this gem has no hard dependency on either of them, or on any
other provider.

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

Everything else is duck typed and supplied by you: `deepl-rb` only if you use
the DeepL provider (the default) and `google-cloud-translate-v2` only if you
use the Google one, each required lazily the first time it is needed, with a
clear error if it is missing. The same is true of `redis` and
`connection_pool` once you configure `redis_url`, and of `ratelimit` on the
first check once you configure `rate_limit`. `redis-namespace` (for the Redis
cache store) goes one step further: this gem never requires it at all, so
your application must `require` it itself before using the Redis-backed
store. See [Getting started](#getting-started) below.

## Installation

Add this line to your application's Gemfile:

```ruby
gem 'translation_diff'
```

And then execute:

    $ bundle

Or install it yourself as:

    $ gem install translation_diff

## Getting started

```ruby
TranslationDiff.configure do |config|
  config.deepl_api_key = ENV["DEEPL_API_KEY"]
  config.redis_url = ENV["REDIS_URL"]
end

TranslationDiff.translate("Привет.", from: "ru", to: "en")
```

Both of those have sensible defaults, so with `DEEPL_AUTH_KEY` and `REDIS_URL`
in the environment there is nothing to configure at all. Without `REDIS_URL`
the cache lives in the process, which means the library runs before any
infrastructure does.

Every extension point takes **either a symbol naming a built-in, or an object
of your own**:

```ruby
TranslationDiff.configure do |config|
  config.provider = :deepl        # or any object satisfying the provider contract
  config.cache = :redis           # or any object satisfying the cache store contract
  config.segmenter = :pragmatic   # or any object satisfying the segmenter contract
end
```

## Configuration options

Every setting lives on the one `Configuration` object yielded by
`TranslationDiff.configure`. An option not assigned falls back to its
default; assigning it a blank string behaves as though it was never touched
at all, so an unset environment variable never has to be special-cased.

| Option | Default | Meaning |
| --- | --- | --- |
| `provider` | `:deepl` | The translation provider: a registered name or an object satisfying the [provider contract](#the-provider-contract). |
| `cache` | `nil` | The cache store: a registered name or an object satisfying the [cache store contract](#the-cache-store-contract). `nil` means "choose for me" -- see below. |
| `cache_ttl` | `604_800` (one week) | Seconds a Redis cache entry is kept. Only meaningful for `RedisCacheStore`; `MemoryCacheStore` evicts by size instead. |
| `cache_namespace` | `"translation-diff"` | Prefix applied to every Redis key this gem writes -- both cache entries and the rate limiter's own bookkeeping. |
| `cache_max_size` | `1_000` | Maximum number of entries `MemoryCacheStore` keeps before evicting the least recently used one. |
| `redis_url` | `ENV["REDIS_URL"]` | Where to connect for the Redis-backed cache store and rate limiter. Setting this is what makes `cache` default to `:redis` instead of `:memory`. |
| `redis_pool_size` | `5` | Size of the connection pool built from `redis_url`. |
| `redis_pool_timeout` | `5` | Seconds to wait for a connection from that pool before raising. |
| `rate_limit` | `nil` | Character threshold per `rate_interval`. Unset means no rate limiting at all. |
| `rate_interval` | `60` | Seconds over which `rate_limit` is measured. **Actually enforced over roughly 5-600 seconds** -- see [The rate limiter contract](#the-rate-limiter-contract). |
| `rate_limiter` | `nil` | An object satisfying the [rate limiter contract](#the-rate-limiter-contract), to use in place of the built-in Redis-backed one. |
| `segmenter` | `:pragmatic` | The sentence segmenter: a registered name or an object satisfying the [segmenter contract](#segmenters-and-the-segmenter-contract). |
| `instrumenter` | `nil` | Anything satisfying `ActiveSupport::Notifications`' `#instrument(name, payload) { }` interface. See [Instrumentation and logging](#instrumentation-and-logging). |
| `logger` | `nil` | A standard `Logger`. Receives one `debug` line per provider resolution, naming the provider class -- never content and never a credential. See [Instrumentation and logging](#instrumentation-and-logging). |

The `:deepl` provider declares two options of its own, registered the moment
`translation_diff` is required:

| Option | Default | Meaning |
| --- | --- | --- |
| `deepl_api_key` | `nil` | Forwarded to `deepl-rb` as `auth_key`. Left unset, `deepl-rb` reads `DEEPL_AUTH_KEY` from the environment itself. |
| `deepl_host` | `nil` | Overrides `deepl-rb`'s automatic free/paid host selection (from the `:fx` suffix on the key). Rarely needed. |

The `:google` provider declares two of its own, on the same terms:

| Option | Default | Meaning |
| --- | --- | --- |
| `google_api_key` | `nil` | Forwarded to `google-cloud-translate-v2` as `key`. Left unset, that gem reads `TRANSLATE_KEY` or `GOOGLE_CLOUD_KEY` from the environment itself, and falls back to application default credentials when there is no key at all. |
| `google_project_id` | `nil` | Only consulted on the credentials path; an API key needs no project. Left unset, the gem reads `TRANSLATE_PROJECT`. |

A provider you register yourself can declare its own options the same way --
see [Registering your own provider](#registering-your-own-provider) below.

**Configure once, before the first translation.** `provider`, `cache`,
`segmenter` and `rate_limiter` each resolve to a collaborator on first use
and that collaborator is memoised for the life of the configuration. Options
stay writable afterwards, but changing one no longer reaches an object that
has already been built: setting `cache_max_size` after something has
translated leaves the store built with the old bound in place, and
reassigning `provider` after a translation has run does not change the
provider that configuration uses. `TranslationDiff.context` -- or
`config.copy`, which it is built on -- is the way to get a configuration that
resolves everything afresh from its own values.

### Choosing the cache store

`cache` unset means "choose for me": `RedisCacheStore` when `redis_url` is
configured, `MemoryCacheStore` otherwise, so the library works before any
infrastructure does. Set `cache` explicitly (`:redis`, `:memory`, or your own
object) to override that choice.

### What a cache key is made of

One entry per sentence, keyed by the provider's `cache_key`, the lowercased
source and target language codes, a digest of the provider options that call
passed (`formality:`, a glossary id, ...), and a digest of the sentence
itself. `RedisCacheStore` prefixes all of that with `cache_namespace`.

**`deepl_host` is deliberately not part of the key.** Two configurations
pointing `deepl_host` at different endpoints share cache entries. For DeepL's
own free and paid hosts that is correct -- they return the same translations
-- but a self-hosted or proxied endpoint may not, and it would be served, and
would serve, the real service's entries. Give such a configuration its own
`cache_namespace` (or its own Redis database). The key format is left alone
here on purpose: changing its shape invalidates every entry already cached,
everywhere, at once.

### The Google provider

`config.provider = :google` translates through Cloud Translation v2 (Basic).
It needs the `google-cloud-translate-v2` gem, which this gem requires lazily
the first time the provider is built:

```ruby
gem "google-cloud-translate-v2", "~> 1.2"
```

```ruby
TranslationDiff.configure do |config|
  config.provider = :google
  config.google_api_key = ENV["GOOGLE_TRANSLATE_KEY"]
end
```

An API key is the whole setup -- no project id, no service account. Leave
`google_api_key` unset and the gem reads `TRANSLATE_KEY` or
`GOOGLE_CLOUD_KEY` itself; with no key anywhere it falls back to application
default credentials, which is the path where `google_project_id` matters.

Two things this provider does on your behalf, both of which would otherwise
be silent problems:

- **It asks for HTML**, which is Google's own default and what this gem has
  always sent. What reaches a provider is not plain text: a `notranslate`
  span arrives whole, tags included -- that is how the tokenizer marks
  content the provider must leave alone -- and entities such as `&amp;`
  stay in the text it emits. Asking for `text` makes Google translate the
  protected span and drop its markup:

  ```
  "<span class='notranslate'>Bold Mountain</span> is a good place."
  format: text  ->  "Болд Маунтин — хорошее место."
  format: html  ->  "<span class='notranslate'>Bold Mountain</span> — хорошее место."
  ```

  The cost is that Google escapes its own output: a literal apostrophe
  returns as `&#39;`. Inside the HTML fragment these values usually are,
  that renders as an apostrophe and is correct. Inside a value that never
  had any markup in it, it is noise -- pass `format: :text` per call when
  translating bare strings.
- **It downcases bare language codes.** Google's codes are lowercase, and a
  configuration written against DeepL says `"EN"`. Codes carrying a subtag
  -- `"zh-Hans"`, `"zh-CN"`, `"pt-BR"` -- are passed through untouched,
  because the casing of a script or region subtag is its own.

Its limits are Google's documented ones: 128 strings per request (a hard
limit -- a larger batch is rejected), and 5,000 characters per request (the
documented recommendation, well under the hard 100 KB ceiling). Chunker
measures the URL-escaped form of each string, which is never smaller than
its UTF-8 byte count, so a chunk within that bound in escaped characters is
within it in bytes as well.

`google_project_id` is not part of the cache key, on the same reasoning as
`deepl_host` above: it selects an account to bill, not a translation.

## Registering your own provider

Any translation service can be a provider -- no change to this gem's own
code is required. Registering a provider also declares the options it needs,
so `config.yandex_api_key` below does not exist until `YandexProvider`
is registered:

```ruby
class YandexProvider
  # Declares this provider's own configuration options. TranslationDiff::Providers.register
  # adds each one to TranslationDiff::Configuration as a side effect.
  def self.configuration_options = %i[yandex_api_key]
  def self.build(config) = new(config.yandex_api_key)

  def initialize(api_key)
    @client = SomeYandexClient.new(key: api_key)
  end

  # Required: translate an array of strings, return one string per input, in
  # the same order. Provider-specific options (formality, glossary, ...)
  # arrive through **options untouched.
  def translate(texts, from:, to:, **options)
    texts.map { |text| @client.translate(text, from: from, to: to)[:text] }
  end

  # Required: this provider's own request- and batch-size limits.
  def max_request_size = 30_000
  def max_batch_size = 128

  # Optional: omit entirely if the provider has no detection endpoint, or if
  # callers of this gem always pass `from:` explicitly.
  def detect(text)
    @client.detect(text)[:language]
  end

  # cache_key is optional too: TranslationDiff::Providers.register mixes a
  # module into any provider that does not define its own #cache_key, and
  # that module stamps every instance built through the registry with its
  # registered name -- nothing here needs to supply one by hand. See
  # "Provider objects and cache_key" below for what happens without it.
end

TranslationDiff::Providers.register(:yandex, YandexProvider)

TranslationDiff.configure do |config|
  config.provider = :yandex
  config.yandex_api_key = ENV["YANDEX_API_KEY"]
end
```

**Provider names must be unique.** `TranslationDiff::Providers.register`
overwrites whatever was previously registered under that name, silently --
there is no error for registering `:deepl` twice. This is deliberate: a
raise would break Rails development-mode reloading and a defensive double
`require`. It also means a typo in a name collides with a real provider
without warning, so choose names as carefully as you would a constant.

What happens when they are not unique is worth being precise about. The last
class registered under the name wins, and it also inherits the cache entries
of the one it replaced: `cache_key` falls back to the registered name, so a
class registered over `:deepl` reads and writes exactly the entries the real
DeepL provider wrote. Callers are then served one service's translations from
another service's cache, for as long as those entries live, with nothing in
the log to say so. Registering over an existing name is not a way to
substitute a service -- give the replacement its own name, or clear the cache
(`cache_namespace` is the cheapest way to do that).

**Option names are unique too, and enforced.** Two providers declaring the
same `configuration_options` name would share one accessor on
`TranslationDiff::Configuration`, which would hand one service's credential
to the other, so registering the second one raises and names both providers
and the option. Prefix your options with your provider's name --
`deepl_api_key`, `google_api_key` -- the way the built-ins do. The same
provider redeclaring its own options is not a conflict: a double `require`
and a Rails reload both re-run registration.

`TranslationDiff::Providers.names` lists every registered provider;
`TranslationDiff::Providers.registered?(:yandex)` checks one.

## The provider contract

`config.provider` accepts either a registered name (`:deepl`, `:google`,
`:null`, or anything you registered yourself) or an object of your own that satisfies
this contract directly, bypassing the registry entirely:

```ruby
# Translates an array of strings and returns an array of strings, one per
# input, in the same order. Provider-specific options (e.g. `formality:`)
# arrive through **options and are passed straight through to the provider.
def translate(texts, from:, to:, **options); end

# Detects the source language of a single string and returns it. Optional:
# omit this method entirely if the provider has no detection endpoint, or if
# callers of this gem always pass `from:` explicitly. When `detect` is
# missing and `from:` is not given, TranslationDiff raises rather than
# guessing.
def detect(text); end

# The largest single request the provider accepts, in characters of the
# escaped form -- which is what the chunker measures (CGI.escape(text).size,
# not String#size). For Cyrillic and other non-Latin text this is 6 to 9
# times the raw character count. Declaring the provider's raw character
# limit here will either waste most of the budget (if you under-report) or
# raise Chunker::Error on text the provider would actually have accepted
# (if you over-report). Used to split long texts into multiple requests.
def max_request_size; end

# The largest number of strings the provider accepts in one batched request.
# Used to split large arrays into multiple requests.
def max_batch_size; end

# A short, stable, non-empty string identifying this provider. Used to
# namespace cache keys, so that switching providers does not return one
# provider's cached translations for another. Not required when a provider
# is only ever built through TranslationDiff::Providers.register -- see
# below.
def cache_key; end
```

`test/support/provider_contract.rb` is the executable form of this contract:
include `ProviderContract` in a test class that defines `#provider`, and it
verifies `translate`, `max_request_size` and `max_batch_size` behave as
documented above.

Two providers ship with this gem: `TranslationDiff::Providers::DeepL` (the
default, registered as `:deepl`), wrapping the
[`deepl-rb`](https://github.com/wikiti/deepl-rb) gem (not a dependency of
this one -- required at build time); and `TranslationDiff::Providers::Null`
(`:null`), which hands back exactly what it was given, for tests and for
wiring up a pipeline before a real provider is available.

### Provider objects and cache_key

A provider built through `TranslationDiff::Providers.build` (which is what
happens when `config.provider` is a symbol) is stamped with its registered
name automatically, and never needs to define `cache_key` itself -- the
registry mixes in a module that supplies it.

A provider object assigned straight to `config.provider` never passes
through the registry, so it gets no name and **must define `cache_key`
itself**, or every call through it raises. This is not pedantry: `cache_key`
is a segment of every cache entry this provider ever reads or writes, so two
providers sharing one -- or both silently falling back to an empty one --
would let a caller be served another provider's cached translation.

## The cache store contract

`config.cache` accepts either a registered name (`:redis`, `:memory`) or an
object satisfying this contract directly:

```ruby
# Reads several keys at once, returning an array the same length as keys,
# with nil in a missing key's position.
def read_multi(keys); end

# Writes one key. The second write of the same key replaces the first.
def write(key, value); end
```

`test/support/cache_store_contract.rb` is the executable form of this
contract: include `CacheStoreContract` in a test class that defines
`#store`.

Two stores ship with this gem: `TranslationDiff::MemoryCacheStore`, the
default -- a bounded, in-process LRU, not thread-safe by design, evicting by
`cache_max_size` rather than by time; and `TranslationDiff::RedisCacheStore`,
built from `redis_url` when that is set, expiring entries after `cache_ttl`
and namespacing every key under `cache_namespace`. Neither `redis` nor
`connection_pool` nor `redis-namespace` is a dependency of this gem --
`RedisCacheStore` takes anything answering to `#with` the way
`ConnectionPool` does, and yields anything `Redis::Namespace` accepts.

## The rate limiter contract

Unlike `provider`, `cache` and `segmenter`, `rate_limiter` does not resolve a
symbol through a registry -- there is only one built-in implementation.
`config.rate_limiter_instance` is:

- the object assigned to `config.rate_limiter`, if any;
- otherwise `nil` if `rate_limit` was never set -- and `Request` checks for
  that `nil` and skips rate limiting entirely, so the common case costs
  nothing;
- otherwise a `TranslationDiff::RedisRateLimiter` built from `rate_limit`,
  `rate_interval`, `redis_url` and `cache_namespace`.

An object assigned to `rate_limiter` must implement:

```ruby
# Called with the number of characters about to be sent to the provider.
# Raises when the caller-defined threshold is exceeded.
def check(size); end
```

`TranslationDiff::RedisRateLimiter` raises
`TranslationDiff::RedisRateLimiter::RateLimitExceeded` when its threshold is
exceeded within its interval. Neither `redis` nor `connection_pool` nor
`ratelimit` is a dependency of this gem: `ratelimit` is required on the first
check, so an application that configures no `rate_limit` never needs it, and
its absence raises `TranslationDiff::Error` naming the gem to add.

**Upgrading to 3.1.0: re-validate your `rate_limit` threshold.** Before this
release, `RedisRateLimiter` never actually limited anything -- a signature
mismatch with the `ratelimit` gem meant it recorded hits under a subject
`exceeded?` never read, so the threshold could never be reached. That bug
shipped in every release since `v1.0.2` (2023-02-16). If you have
`rate_limit` configured, your traffic has never actually been throttled by
it; upgrading makes the limiter fire for the first time, against a value you
may have set once and never seen exercised. Re-check that the threshold
still reflects the traffic you actually want to allow before you upgrade.

**`rate_interval` is silently clamped to roughly 5-600 seconds.** The
built-in limiter constructs `Ratelimit.new` with no bucket options, so the
gem's own fixed bucket span applies regardless of what you configure --
measured: `rate_interval: 3600` behaves as `600`, and `rate_interval: 1`
behaves as `5`. Combined with the fix above, an interval configured above
600 seconds is now enforced over 600 seconds instead, which trips the
limiter up to six times more eagerly than the configured value suggests.
Keep `rate_interval` within 5-600 seconds if you want the configured number
to be the enforced one.

## Segmenters and the segmenter contract

`config.segmenter` decides where a text node is cut into sentence-sized
cache units, the same way `config.provider` decides how a sentence gets
translated. It defaults to `:pragmatic` and can be swapped for `:simple` or
for any object implementing:

```ruby
# Returns the offsets at which a new sentence begins, always starting with 0
# and strictly increasing. Slicing the source between consecutive offsets, and
# from the last offset to the end, reconstructs the source exactly -- a wrong
# boundary never corrupts the document, it only changes how the text is
# grouped into cache units.
#
# language: is an ISO 639-1 code such as "en" or "ru" when the caller already
# knows the source language, and nil when it does not -- see below.
def split_offsets(text, language: nil); end
```

Two segmenters ship with this gem:

- **`TranslationDiff::Segmenters::Pragmatic`** (the default) wraps the
  [`pragmatic_segmenter`](https://github.com/diasks2/pragmatic_segmenter) gem,
  which ships per-language rule sets rather than one rule set applied to every
  script. Measured against the Golden Rules corpus, the de-facto benchmark for
  sentence segmentation -- the `context "Golden Rules" do` block of each of
  the 10 per-language spec files on `diasks2/pragmatic_segmenter`, 80
  exemplars in total; a sample of the same corpus is in
  `test/translation_diff/golden_rules_test.rb` -- it scores 76/80 against
  `Simple`'s 47/80, and the gap is largest on languages that have no letter
  case at all -- Arabic, Hindi, Armenian, Greek -- which `Simple` cannot
  reason about by design.

  Of the 4 exemplars `Pragmatic` misses, 3 are not boundary disagreements at
  all: `pragmatic_segmenter`'s own expected value rewrites an incidental
  newline into a space before comparing --

      "This is a sentence\ncut off in the middle because pdf."
        expected ["This is a sentence cut off in the middle because pdf."]
        ours     ["This is a sentence\ncut off in the middle because pdf."]

      "It was a cold \nnight in the city."
        expected ["It was a cold night in the city."]
        ours     ["It was a cold \nnight in the city."]

  -- and the same shape recurs once in Japanese (`"これは父の\n家です。"`, expected
  with the newline gone). In all three, `Pragmatic` finds exactly one
  sentence, agrees on where it ends, and is scored wrong only because it
  will not rewrite the source to match. Rewriting the source is exactly what
  this gem's reconstruction invariant forbids, so this is a deliberate
  choice, not a defect the score is hiding. The 1 remaining miss is a real
  boundary disagreement, in English -- see the shadowing paragraph below.

  Before segmenting, `Pragmatic` replaces every single newline (one with no
  adjoining newline) with a space in a shadow copy of the text, segments the
  shadow, and slices the *original* text at the recovered offsets --
  `pragmatic_segmenter` otherwise treats almost any single newline as a
  sentence boundary candidate even with no punctuation at all, which is a
  false split (the harmful kind) on the incidental newlines that HTML text
  nodes routinely carry from source formatting. A run of two or more
  newlines (a real paragraph break) is left alone. This costs one Golden
  Rules point (77 -> 76): one exemplar shaped like a bare list of items
  separated by single newlines, with no punctuation, now segments as one
  unit instead of three. That shape does not arise in this gem's actual
  input -- HTML list items are separated by markup into distinct text nodes
  already -- so the point is a deliberate trade, not a regression to chase.

  Language codes are normalised before reaching `pragmatic_segmenter`:
  downcased, with any region subtag after `-` or `_` dropped, and checked
  against the codes `pragmatic_segmenter` actually has rules for, falling
  back to English otherwise. DeepL -- this gem's own flagship provider --
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
stops at the first one it cannot -- but the boundary at the end of the last
sentence it did locate is not thrown away with the rest, since it was
matched character for character too. Only the genuinely unrecoverable
remainder is coarsened into one final unit; the verified prefix before it is
still sliced off. This is a *coarsening*, not a failure -- the text still
translates correctly, the cache unit is just larger than it could have
been -- and it is silent by design,
the same way a segmenter simply not splitting a node has always been
acceptable. `TranslationDiff::Segmenters::Pragmatic::Error` (a
`TranslationDiff::Error`) still exists and is still raised, but only if
`Pragmatic` itself computes offsets that violate its own postcondition
(starting at 0, strictly increasing, all within the text) -- not by ordinary
use of `pragmatic_segmenter`, however it rewrites a sentence.

## Contexts

`TranslationDiff.context` returns a `TranslationDiff::Context`: an isolated
configuration scope with the same `#translate` entry point as the
`TranslationDiff` module itself, for multi-tenant applications and
per-request overrides. It starts from a copy of the global configuration, so
it inherits every value already set, and changes made inside it never touch
the global configuration:

```ruby
tenant = TranslationDiff.context { |config| config.deepl_api_key = tenant_key }
tenant.translate("Hello.", from: "en", to: "ru")

TranslationDiff.config.deepl_api_key # unchanged
```

**The block is required.** `TranslationDiff.context` yields the copy for you
to configure and there is nothing useful to hand back without one -- a copy
nobody configured is just the global configuration. Called without a block it
raises `LocalJumpError`.

**A context starts with a cold cache.** Copying a configuration carries its
option *values* over, but deliberately not the collaborators already built
from them -- each context resolves its own provider, cache store, segmenter
and rate limiter from its own values, independently of whatever the
configuration it was copied from had already built. When `cache` is left
unset, that resolves to `MemoryCacheStore`, an in-process store, so a freshly
built context's store starts empty every time -- a short-lived, per-request
context therefore caches nothing across requests. Configure `redis_url` (or
assign one shared cache object explicitly) if contexts need to share a
cache.

**An object assigned directly is shared; a name is not.** Assign
`config.cache`, `config.provider`, `config.segmenter` or `config.rate_limiter`
a symbol and every context builds its own instance from it. Assign an
*object* instead and that exact object -- the same connection pool, the same
client -- is carried into every context copied from that configuration:
someone who hands this library one connection pool means one connection
pool.

## Instrumentation and logging

`config.instrumenter` accepts anything satisfying
`ActiveSupport::Notifications`' interface -- `#instrument(name, payload) { }` --
and `config.logger` accepts a standard `Logger`. Neither is required: with
both unset, `TranslationDiff.translate` runs exactly the same, at no extra
cost.

A translation emits up to four events, each named `<name>.translation_diff`:

| Event | Fired | Payload |
| --- | --- | --- |
| `translate` | Once per `translate` call that reaches the provider, wrapping the whole thing. A call whose source and target languages are the same, or whose values hold no translatable text at all, returns early and emits no events. | `from`, `to`, `provider`, `values` (number of texts) |
| `cache` | Once per chunk, after checking the cache. | `provider`, `hits`, `misses` |
| `request` | Once per chunk actually sent to the provider (skipped entirely on a full cache hit). | `provider`, `batch` (values sent), `characters` |
| `rate_limit` | Once per chunk sent to the provider, only when a rate limiter is configured. | `provider`, `characters` |

**Instrumentation payloads never contain the text being translated, its
translation, or a credential.** This is a guarantee, not an implementation
detail: this library handles other people's content, and an instrumenter
usually writes somewhere that content must not go. Only counts, language
codes and provider names cross that boundary.

`config.logger` receives one `debug` line per provider resolution, naming
the provider class in use -- nothing about the content being translated. The
same guarantee applies to it as to instrumentation payloads: no log line this
library writes carries the text being translated, its translation, or a
credential.

**deepl-rb has request logging of its own, and this library deliberately
does not enable it.** `config.logger` is never passed to `deepl-rb`. Given a
logger, `deepl-rb` writes a `Request details:` line at DEBUG holding the full
`Authorization: DeepL-Auth-Key ...` header and the request payload -- your API
key and the text being translated. Forwarding this gem's logger into it would
break the guarantee above at the exact moment someone raises the log level to
diagnose a problem, which is why the provider does not.

If you want that log anyway, ask for it explicitly: build the `DeepL::API`
yourself, wrap it in the provider, and assign the object.

```ruby
api = DeepL::API.new(
  DeepL::Configuration.new(auth_key: ENV["DEEPL_AUTH_KEY"], logger: verbose_logger)
)

provider = TranslationDiff::Providers::DeepL.new(api)
provider.name = :deepl # the cache key a registry-built provider gets for free

TranslationDiff.configure { |config| config.provider = provider }
```

Everything `verbose_logger` then receives -- source text, translations, and
the auth key -- goes wherever it writes. Point it somewhere disposable, not at
the application log, and do not leave it on.

## Errors

Every error this gem raises inherits from `TranslationDiff::Error < StandardError`,
so rescuing the gem's failures in one clause is a single `rescue TranslationDiff::Error`:

```
TranslationDiff::Error
├── TranslationDiff::Request::Error            # e.g. provider returned the wrong number of
│                                               # translations, from: missing and the
│                                               # provider cannot detect, cache_key
│                                               # missing on an assigned provider object
├── TranslationDiff::Cache::Error              # provider options have no stable
│                                               # serialisation for the cache key
├── TranslationDiff::Chunker::Error            # a single value is larger than the
│                                               # provider's max_request_size
├── TranslationDiff::Segmenters::Pragmatic::Error
│                                               # Pragmatic computed offsets that
│                                               # violate its own postcondition --
│                                               # not raised by ordinary use
└── TranslationDiff::RedisRateLimiter::RateLimitExceeded
                                                # the configured rate_limit was exceeded
```

`TranslationDiff::Registry` -- which backs the provider, cache store and
segmenter registries -- also raises `TranslationDiff::Error` directly (not a
dedicated subclass) for an unknown name, listing what is actually
registered.

## How it works

- Text nodes are extracted from HTML.
- Every text node is split into sentences by `config.segmenter` (see
  [Segmenters and the segmenter contract](#segmenters-and-the-segmenter-contract)).
- Cache is checked for the presence of each sentence (using language couple and a hash of string).
- Missing sentences are translated via the provider and cached.
- Original HTML is recombined from translations and cache data.

*NOTE:* if `:from` is not specified or equal to nil, then the provider's `#detect` will be called once with a sample of text up to 100 characters long to determine the language, and `#translate` will be called separately with the entire text.
        Try to specify `:from` explicitly to save the extra call -- it also improves segmentation, since the segmenter only sees a language when `:from` is given (see [Segmenters and the segmenter contract](#segmenters-and-the-segmenter-contract)).

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

## Very long texts

Every provider limits how large a single request or a single batch can be.
Providers state their own limits through `#max_request_size` and
`#max_batch_size`; if your text is longer than that, TranslationDiff splits it
into multiple requests automatically. The DeepL provider, for example, caps
requests at 1700 characters and batches at 300 sentences.

## Former name and upgrading

This gem was published as `deepl_diff` through 2.2.0. `deepl_diff` is
deprecated in favor of `translation_diff`, which is functionally the same
gem under a name that no longer implies a dependency on DeepL specifically.

**Upgrading from `deepl_diff`:** every cache key changed in 3.1.0 -- the
provider, the provider options and normalised language codes are now part of
the key. Nothing cached previously is reused; the next translation of every
sentence is a cache miss, once, everywhere. `TranslationDiff.api`, `.cache_store`,
`.segmenter` and `.rate_limiter` -- the four module-level accessors earlier
versions configured directly -- are gone; configure `TranslationDiff.config`
(or use `TranslationDiff.configure`) instead. If you have `rate_limit`
configured, also read the upgrading note in
[The rate limiter contract](#the-rate-limiter-contract): the limiter was
never actually enforcing your threshold before 3.1.0, and it starts doing so
now. See [CHANGELOG.md](CHANGELOG.md) for the full list of breaking changes.

## Development

After checking out the repo, run `bin/setup` to install dependencies. Then, run `rake test` to run the tests. You can also run `bin/console` for an interactive prompt that will allow you to experiment.

To install this gem onto your local machine, run `bundle exec rake install`. To release a new version, update the version number in `version.rb`, and then run `bundle exec rake release`, which will create a git tag for the version, push git commits and tags, and push the `.gem` file to [rubygems.org](https://rubygems.org).

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/Halvanhelv/translation_diff.
