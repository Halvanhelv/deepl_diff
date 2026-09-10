# Caching

## What a cache key is made of

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

Both read and write the same cache, keyed per provider, so switching one
never serves you the other's translations.

`TranslationDiff::SentenceCache` is the class that builds the key and does
both the read and the write.

## The options digest is lossy, on purpose

The per-call options are canonicalised to a string before they are digested,
and that canonical form flattens more than it distinguishes. Nesting is not
recorded, so `["x", ["y", "z"]]` and `["x", "y", "z"]` canonicalise
identically; neither is emptiness typed, so `tags: []` and `tags: {}` do
too. Two calls whose options differ only in one of those ways share a cache
entry.

This is a known property, not an oversight. The pipeline this replaced
collides on exactly the same inputs -- that was checked, not assumed -- so
reproducing it was the choice that left every warm cache warm. Fixing it
would give those calls new keys and re-translate everything already cached
under the old ones, for a distinction no provider option this gem ships
actually makes. If you pass an option where that distinction matters, give
the configuration its own `cache_namespace`.

A value the canonical form cannot render at all -- anything that is not a
String, Symbol, Numeric, `true`, `false`, `nil`, or an Array or Hash of
those -- raises `TranslationDiff::SentenceCache::Error` rather than being
guessed at. A key that is silently wrong costs you the whole cache and tells
you nothing.

No options at all contributes no field to the key, which is the four-field
key every already-warm cache is keyed on.

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
