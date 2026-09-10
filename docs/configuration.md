# Configuration

Everything here is configured through the one `Configuration` object yielded by `TranslationDiff.configure`.

## Dependencies

This gem loads four at require time: [`ox`](https://github.com/ohler55/ox) to
walk the HTML; [`pragmatic_segmenter`](https://github.com/diasks2/pragmatic_segmenter),
which backs the default sentence segmenter and has zero dependencies of its
own (see [The segmenter contract](contracts.md#the-segmenter-contract)
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

## Getting started

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
| `provider` | `:deepl` | The translation provider: a registered name or a `TranslationDiff::Provider` of your own. See [Providers](providers.md). |
| `cache` | `nil` | The cache store: a registered name or an object satisfying the [cache store contract](caching.md#the-cache-store-contract). `nil` means "choose for me" -- see below. |
| `cache_ttl` | `604_800` (one week) | Seconds a Redis cache entry is kept. Only meaningful for `RedisCacheStore`; `MemoryCacheStore` evicts by size instead. |
| `cache_namespace` | `"translation-diff"` | Prefix applied to every Redis key this gem writes -- both cache entries and the rate limiter's own bookkeeping. |
| `cache_max_size` | `1_000` | Maximum number of entries `MemoryCacheStore` keeps before evicting the least recently used one. |
| `cache_table_name` | `"translation_diff_translations"` | Table `ActiveRecordCacheStore` reads and writes. For a host with its own table-naming convention. See [SQL cache](sql-cache.md). |
| `rate_limit_table_name` | `"translation_diff_rate_limits"` | Table `ActiveRecordRateLimiter` reads and writes. As above. |
| `active_record_base` | `nil` (`::ActiveRecord::Base`) | The class `ActiveRecordCacheStore` and `ActiveRecordRateLimiter` build their model from -- point this at a second database, or a reader/writer role. See [SQL cache](sql-cache.md#active_record_base-a-second-database-or-a-readerwriter-role). |
| `cache_prune_probability` | `0.0` | Chance, per write, that `ActiveRecordCacheStore` prunes expired rows before returning. `0.0` is off; `rake translation_diff:prune` is the other way to prune. See [SQL cache](sql-cache.md#pruning-three-answers-none-imposed). |
| `redis_url` | `ENV["REDIS_URL"]` | Where to connect for the Redis-backed cache store and rate limiter. Setting this is what makes `cache` default to `:redis` instead of `:memory`. |
| `redis_pool_size` | `5` | Size of the connection pool built from `redis_url`. |
| `redis_pool_timeout` | `5` | Seconds to wait for a connection from that pool before raising. |
| `rate_limit` | `nil` | Character threshold per `rate_interval`. Unset means no rate limiting at all. |
| `rate_interval` | `60` | Seconds over which `rate_limit` is measured. **Actually enforced over roughly 5-600 seconds** -- see [The rate limiter contract](contracts.md#the-rate-limiter-contract). |
| `rate_limiter` | `nil` | A registered name (`:redis`, `:active_record`) or an object satisfying the [rate limiter contract](contracts.md#the-rate-limiter-contract). `nil` with `rate_limit` set resolves to `:redis`. |
| `segmenter` | `:pragmatic` | The sentence segmenter: a registered name or an object satisfying the [segmenter contract](contracts.md#the-segmenter-contract). |
| `instrumenter` | `nil` | Anything satisfying `ActiveSupport::Notifications`' `#instrument(name, payload) { }` interface. See [Instrumentation and logging](instrumentation.md). |
| `logger` | `nil` | A standard `Logger`. Receives one `debug` line per provider resolution, naming the provider class -- never content and never a credential. See [Instrumentation and logging](instrumentation.md). |
| `open_timeout` | `5` | Seconds an HTTP-backed provider waits to open a connection before raising `TranslationDiff::TransportError`. |
| `timeout` | `30` | Seconds an HTTP-backed provider waits for a response before raising `TranslationDiff::TransportError`. |
| `max_retries` | `3` | Retries `faraday-retry` attempts on a transport failure or a `429`/`500`/`502`/`503`/`504` response, with exponential backoff. `faraday-retry` honours a `Retry-After` header itself, so a `429` usually exhausts its retries before `TranslationDiff::RateLimitError` is ever raised. |
| `validate_languages` | `true` | Whether `translate` refuses a source/target pair the shipped data doesn't list, before making a request. See [Languages](languages.md). |

## Provider options

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
see [Writing a provider](providers.md#writing-a-provider) below.

## Configure once, before the first translation

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

## Choosing the cache store

`cache` unset means "choose for me": `RedisCacheStore` when `redis_url` is
configured, `MemoryCacheStore` otherwise, so the library works before any
infrastructure does. Set `cache` explicitly (`:redis`, `:memory`, or your own
object) to override that choice.

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
