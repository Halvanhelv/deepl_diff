# TranslationDiff

A translation cache that helps translate only changes between revisions of
long texts. It ships with six providers -- DeepL, Google Cloud Translation,
Azure AI Translator, ModernMT, LibreTranslate and Amazon Translate -- but any
translation service can be plugged in by subclassing a small base class; see
[Providers](#providers).

**TranslationDiff** based on [GoogleTranslateDiff](https://github.com/gzigzigzeo/google_translate_diff)

## Use case

Assume your project contains a significant amount of products descriptions which:
- Require retranslation each time user edits them.
- Have a lot of equal parts (like return policy).
- Change frequently.

If your user changes a single word within the long description, you will be charged for the retranslation of the whole text.

Much better approach is to try to translate every repeated structural element (sentence) in your texts array just once to save money. This gem helps to make it done.

## Dependencies

This gem loads four at require time: [`ox`](https://github.com/ohler55/ox) to
walk the HTML; [`pragmatic_segmenter`](https://github.com/diasks2/pragmatic_segmenter),
which backs the default sentence segmenter and has zero dependencies of its
own (see [Segmenters and the segmenter contract](#segmenters-and-the-segmenter-contract)
below if you want to avoid it); and [`faraday`](https://github.com/lostisland/faraday)
with [`faraday-retry`](https://github.com/lostisland/faraday-retry), the HTTP
transport every REST-backed provider (DeepL, Google, Azure, ModernMT,
LibreTranslate) inherits and owns directly -- none of them wraps a
vendor-supplied SDK any more.

Everything else is duck typed and supplied by you: `aws-sigv4`, required
lazily the first time the Amazon provider signs a request, with a clear
error if it is missing. The same is true of `redis` and `connection_pool`
once you configure `redis_url`, and of `ratelimit` on the first check once
you configure `rate_limit`. `redis-namespace` (for the Redis cache store)
goes one step further: this gem never requires it at all, so your
application must `require` it itself before using the Redis-backed store.
See [Getting started](#getting-started) below.

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

`deepl_api_key` is required -- the provider checks for it at build time and
raises `TranslationDiff::ConfigurationError` naming what is missing, rather
than failing on the first real request. Leave it unset and `DEEPL_AUTH_KEY`
is read instead, on use rather than at load, so the variable may be exported
after this gem is required. `redis_url` is optional: without it
the cache lives in the process, which means the library runs before any
infrastructure does.

Every extension point takes **either a symbol naming a built-in, or an object
of your own**:

```ruby
TranslationDiff.configure do |config|
  config.provider = :deepl        # or any TranslationDiff::Provider of your own -- see Providers
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
| `provider` | `:deepl` | The translation provider: a registered name or a `TranslationDiff::Provider` of your own. See [Providers](#providers). |
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
| `open_timeout` | `5` | Seconds an HTTP-backed provider waits to open a connection before raising `TranslationDiff::TransportError`. |
| `timeout` | `30` | Seconds an HTTP-backed provider waits for a response before raising `TranslationDiff::TransportError`. |
| `max_retries` | `3` | Retries `faraday-retry` attempts on a transport failure or a `429`/`500`/`502`/`503`/`504` response, with exponential backoff. `faraday-retry` honours a `Retry-After` header itself, so a `429` usually exhausts its retries before `TranslationDiff::RateLimitError` is ever raised. |

Every provider declares its own configuration options, registered the moment
`translation_diff` is required:

| Provider | Options | Meaning |
| --- | --- | --- |
| `:deepl` | `deepl_api_key` (required) | Sent as `DeepL-Auth-Key`. Falls back to `ENV["DEEPL_AUTH_KEY"]`. |
| | `deepl_api_base` | Overrides the automatic free/paid host selection (from the `:fx` suffix on the key). Rarely needed. |
| `:google` | `google_api_key` (required) | Sent as the `key` query parameter. Falls back to `ENV["TRANSLATE_KEY"]`, then `ENV["GOOGLE_CLOUD_KEY"]`. |
| | `google_project_id` | Declared for a future credentials path; not currently read -- an API key needs no project. Falls back to `ENV["TRANSLATE_PROJECT"]`. |
| | `google_api_base` | Overrides the default `https://translation.googleapis.com`. |
| `:azure` | `azure_api_key` (required) | Sent as `Ocp-Apim-Subscription-Key`. |
| | `azure_region` | Sent as `Ocp-Apim-Subscription-Region`. Required by a multi-service Azure resource; a single-service resource needs no region. |
| | `azure_api_base` | Overrides the default `https://api.cognitive.microsofttranslator.com`. |
| `:modernmt` | `modernmt_api_key` (required) | Sent as `MMT-ApiKey`. |
| | `modernmt_api_base` | Overrides the default `https://api.modernmt.com`. |
| `:libretranslate` | `libretranslate_api_base` (required) | Every instance is self-hosted; there is no default to fall back to. |
| | `libretranslate_api_key` | Sent as `api_key` in the request body. Most instances do not require one. |
| `:amazon` | `amazon_access_key_id`, `amazon_secret_access_key`, `amazon_region` (all required) | Used to sign each request with `aws-sigv4`. No environment fallback: this library does not implement the AWS credential chain, so `AWS_ACCESS_KEY_ID` and friends are not read. |
| | `amazon_session_token` | For temporary credentials. |
| | `amazon_api_base` | Overrides the default `https://translate.<amazon_region>.amazonaws.com`. |

A provider you register yourself can declare its own options the same way --
see [Writing a provider](#writing-a-provider) below.

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

**No provider's `*_api_base` option is part of the key.** Two configurations
pointing `deepl_api_base` (or any other provider's `_api_base`) at different
endpoints share cache entries. For DeepL's own free and paid hosts that is
correct -- they return the same translations -- but a self-hosted or proxied
endpoint may not, and it would be served, and would serve, the real
service's entries. Give such a configuration its own `cache_namespace` (or
its own Redis database). The key format is left alone here on purpose:
changing its shape invalidates every entry already cached, everywhere, at
once.

## Providers

Every provider declares what it can do through
`TranslationDiff::Capabilities` -- there is nowhere else these numbers live,
so this table is generated from the same source the library reads at
runtime:

| Provider | `config.provider` | Auth option(s) | Batch size | Request size (escaped chars) | HTML support | `notranslate` | Detects language | Reports billing |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Null | `:null` | none | 1,000,000 | 1,000,000 | no | no | no | no |
| DeepL | `:deepl` (default) | `deepl_api_key` | 50 | 1,700 | yes (`tag_handling`) | yes | yes | yes |
| Google | `:google` | `google_api_key` | 128 | 5,000 | yes (`format`) | yes | yes | no |
| Azure | `:azure` | `azure_api_key` | 1,000 | 50,000 | yes (`textType`) | yes | yes | yes |
| ModernMT | `:modernmt` | `modernmt_api_key` | 128 | 5,000 | yes (`format`) | no | yes | yes |
| LibreTranslate | `:libretranslate` | `libretranslate_api_base` | 50 | 5,000 | yes (`format`) | no | yes | no |
| Amazon | `:amazon` | `amazon_access_key_id`, `amazon_secret_access_key`, `amazon_region` | 1 | 10,000 | no | no | yes | no |

**`usage.billed_characters` is `nil` when the provider said nothing about
billing and a number -- `0` included -- when it said something.** All three
providers that report billing follow that rule; the other four always answer
`nil`.

**Language codes are normalised per vendor, so switching provider needs no
other change.** A bare code (`"EN"`, `:ru`) is cased the way the vendor
documents it -- DeepL takes upper case, every other provider here takes lower
case -- whichever casing you wrote. A code carrying a script or region subtag
(`"zh-Hans"`, `"pt-BR"`) is passed through untouched, because the casing of a
subtag is its own. A provider of your own gets the same rule from
`TranslationDiff::Provider#language`; declare `def self.language_case =
:upcase` if your vendor wants upper case.

"Request size" is what `Chunker` measures: the URL-escaped form of each
string (`CGI.escape(text).size`), which is never smaller than its UTF-8 byte
count. "HTML support" names the provider option that turns HTML handling on
-- every vendor spells it differently, which is exactly what
`Capabilities#html` is for. A provider whose "Detects language" column says
no makes `from:` required; passing it makes every provider's `#detect` call
unnecessary regardless of whether it has one.

**Amazon translates one text per call and honours no `notranslate`.** There
is no batch form of `TranslateText`, so a hundred sentences are a hundred
requests -- slow, but correct, and `Capabilities#max_batch_size` reflects
it. Amazon also has no HTML mode: a `notranslate` span reaches it as plain
text and is translated like everything else, tags and all. Both facts are
worth weighing before your bill and your brand names arrive, not after.

**LibreTranslate does not honour `notranslate` either -- measured, not
assumed.** Its HTML format preserves markup, but probing a real instance
(`docker run libretranslate/libretranslate --load-only en,ru`) with
`<span class="notranslate">Bold Mountain</span> is a good place.` came back
with the span tag intact and its content translated anyway -- "Bold
Mountain" became "Смелая гора". The tags survive; what they were meant to
protect does not.

ModernMT's `notranslate: false` is the conservative default rather than a
measurement: it documents an HTML format but says nothing about
`class="notranslate"`, and no key was available to probe it. A capability
that under-promises costs a warning; one that over-promises costs a
customer's protected content reaching a competitor's brand voice.

### Writing a provider

Any translation service can be a provider -- no change to this gem's own
code is required. Subclass `TranslationDiff::HTTPProvider` for a REST
service; it owns the Faraday connection, retries, timeouts and turns HTTP
status codes into this library's error hierarchy, and asks only for three
seams per operation: the URL, how to render a request, how to parse a
reply. Subclass `TranslationDiff::Provider` directly for anything that
reaches its service some other way -- signed requests, another gem, an
LLM client -- and implement `#translate` outright, the way
`TranslationDiff::Providers::Amazon` does.

Registering a provider also declares the options it needs, so
`config.yandex_api_key` below does not exist until `YandexProvider` is
registered:

```ruby
class YandexProvider < TranslationDiff::HTTPProvider
  # Declares this provider's own configuration options.
  # TranslationDiff::Providers.register adds each one to
  # TranslationDiff::Configuration as a side effect.
  def self.configuration_options = %i[yandex_api_key]
  def self.configuration_requirements = %i[yandex_api_key]

  # What this provider can do, checked once by the pipeline for chunking,
  # detection and cache-key safety.
  def self.capabilities
    TranslationDiff::Capabilities.new(
      max_request_size: 10_000, max_batch_size: 100, max_text_size: nil,
      html: :format, notranslate: true, detects_language: true,
      reports_billing: false
    )
  end

  def api_base = "https://translate.api.cloud.yandex.net"
  def headers = { "Authorization" => "Api-Key #{config.yandex_api_key}" }
  def translate_url = "translate/v2/translate"

  # The three seams: build the request body, decode the reply.
  def render_translate_payload(request)
    { format: "HTML", texts: request.texts, targetLanguageCode: request.to.to_s }
      .tap { |body| body[:sourceLanguageCode] = request.from.to_s unless request.from.nil? }
  end

  def parse_translate_response(body, _headers, request)
    translations = Array(body["translations"])

    TranslationDiff::Translation::Response.build(
      request: request,
      texts: translations.map { |t| t["text"] },
      detected_source: translations.first&.dig("detectedLanguageCode")&.downcase
    )
  end

  def detect_url = "translate/v2/detect"

  def detect(text)
    response = post(detect_url, { text: text })
    response.body["languageCode"]&.downcase
  end

  # cache_key is optional: TranslationDiff::Providers.register stamps every
  # instance built through the registry with its registered name, and
  # Provider#cache_key falls back to that. Define it yourself only if this
  # provider will also be instantiated and assigned directly, bypassing the
  # registry -- see "Provider objects and cache_key" below.
end

TranslationDiff::Providers.register(:yandex, YandexProvider)

TranslationDiff.configure do |config|
  config.provider = :yandex
  config.yandex_api_key = ENV["YANDEX_API_KEY"]
end
```

`translate_url`/`render_translate_payload`/`parse_translate_response` are
the three seams `HTTPProvider#translate` calls in order; `detect` is
entirely optional -- omit it (and leave `capabilities.detects_language:
false`) if the provider has no detection endpoint, or if callers of this
gem always pass `from:` explicitly.

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

**An option can declare a default.** A bare symbol in
`configuration_options` declares an option with no default. Writing
`key => default` instead declares one, and a callable default is evaluated on
every read rather than at load time -- which is what lets an environment
variable work when the application exports it after requiring this gem:

```ruby
def self.configuration_options
  [:yandex_api_base, { yandex_api_key: -> { ENV.fetch("YANDEX_API_KEY", nil) } }]
end
```

An explicitly configured value always wins over a default, and a default that
resolves to a blank string reads as unset -- the same rule assignment follows.

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

`test/support/provider_contract.rb` and `test/support/http_provider_contract.rb`
are the executable form of the provider contract: include `ProviderContract`
(and, for an `HTTPProvider` subclass, `HTTPProviderContract`) in a test class
that defines `#provider`, and they verify a provider inherits
`TranslationDiff::Provider`, that `#translate` preserves order and returns
one string per input, and that its declared capabilities are internally
consistent (a provider claiming `notranslate` must also claim an HTML mode).

### Provider objects and cache_key

A provider built through `TranslationDiff::Providers.build` (which is what
happens when `config.provider` is a symbol) is stamped with its registered
name automatically, and never needs to define `cache_key` itself --
`Provider#cache_key` falls back to that stamped name.

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

**No HTTP-backed provider ever receives `config.logger`, and there is no way
to opt one in.** `TranslationDiff::HTTPProvider` installs no logging
middleware on its Faraday connection and never passes a logger to it -- this
is enforced by `test/support/http_provider_contract.rb`, not merely
documented. Earlier versions wrapped `deepl-rb`, which logged a
`Request details:` line at DEBUG holding the full
`Authorization: DeepL-Auth-Key ...` header and the request payload -- your
API key and the text being translated -- if you gave it a logger of its own.
Owning the transport directly closed that door rather than working around
it: nothing this library builds writes source text, a translation, or a
credential anywhere, and no configuration option reopens that.

## Errors

Every error this gem raises inherits from `TranslationDiff::Error < StandardError`,
so rescuing the gem's failures in one clause is a single `rescue TranslationDiff::Error`:

```
TranslationDiff::Error
├── TranslationDiff::ConfigurationError         # a provider is missing a required option
├── TranslationDiff::ProviderError              # the service answered and said no
│   ├── AuthenticationError                     # 401/403
│   ├── RateLimitError                          # 429, once faraday-retry's own retries
│   │                                            # are exhausted -- carries #retry_after
│   │                                            # when the service sent one
│   ├── QuotaExceededError                      # 456
│   ├── InvalidRequestError                     # any other 4xx
│   └── ServiceError                            # 5xx, or anything else
├── TranslationDiff::TransportError             # nobody answered: connection failed,
│                                                # timed out, or TLS failed
├── TranslationDiff::ResponseError              # the answer was well-formed HTTP but broke
│                                                # this library's contract -- a body that
│                                                # is not JSON, a provider that returned
│                                                # the wrong number of translations, or one
│                                                # that returned no translation for an input
├── TranslationDiff::InvalidProviderError       # a class registered without inheriting
│                                                # TranslationDiff::Provider
├── TranslationDiff::Request::Error             # from: missing and the provider cannot
│                                                # detect, cache_key missing on an
│                                                # assigned provider object
├── TranslationDiff::Cache::Error               # provider options have no stable
│                                                # serialisation for the cache key
├── TranslationDiff::Chunker::Error             # a single value is larger than the
│                                                # provider's declared max_request_size
├── TranslationDiff::Segmenters::Pragmatic::Error
│                                                # Pragmatic computed offsets that
│                                                # violate its own postcondition --
│                                                # not raised by ordinary use
└── TranslationDiff::RedisRateLimiter::RateLimitExceeded
                                                 # the configured rate_limit was exceeded
```

`ProviderError` and its subclasses carry `#provider` (the registered name)
and `#status` (the HTTP status code), so a caller can log or branch on which
service and which response caused the failure without parsing the message.

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

Every provider limits how large a single request or a single batch can be,
declared through `TranslationDiff::Capabilities#max_request_size` and
`#max_batch_size`; if your text is longer than that, TranslationDiff splits
it into multiple requests automatically. See the [provider
table](#providers) for each built-in provider's actual numbers -- DeepL, for
example, caps requests at 1,700 escaped characters and batches at 50
sentences.

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

**If you registered a custom provider,** it must now subclass
`TranslationDiff::Provider` (or `TranslationDiff::HTTPProvider`), declare
`self.capabilities`, and implement `#translate(request)` taking a
`TranslationDiff::Translation::Request` and returning a
`TranslationDiff::Translation::Response` -- the duck-typed
`#translate(texts, from:, to:, **options)` plus `#max_request_size` and
`#max_batch_size` methods are no longer read at all. See [Writing a
provider](#writing-a-provider).

## Development

After checking out the repo, run `bin/setup` to install dependencies. Then, run `rake test` to run the tests. You can also run `bin/console` for an interactive prompt that will allow you to experiment.

To install this gem onto your local machine, run `bundle exec rake install`. To release a new version, update the version number in `version.rb`, and then run `bundle exec rake release`, which will create a git tag for the version, push git commits and tags, and push the `.gem` file to [rubygems.org](https://rubygems.org).

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/Halvanhelv/translation_diff.
