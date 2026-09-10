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

`config.cache` accepts either a registered name (`:redis`, `:memory`,
`:active_record`) or an object satisfying this contract directly:

```ruby
# Reads several keys at once, returning an array the same length as keys,
# with nil in a missing key's position.
def read_multi(keys); end

# Writes one key. The second write of the same key replaces the first.
def write(key, value); end

# Writes several pairs at once. Optional -- see "write_multi is optional" below.
def write_multi(pairs); end
```

`test/support/cache_store_contract.rb` is the executable form of this
contract: include `CacheStoreContract` in a test class that defines
`#store`. It only exercises `read_multi` and `write` -- the two required
methods -- so a store that implements only those two still passes it.
`test/support/batching_cache_store_contract.rb` holds the optional half:
include `BatchingCacheStoreContract` too, alongside `CacheStoreContract`,
once `#store` also implements `write_multi`.

Three stores ship with this gem: `TranslationDiff::MemoryCacheStore`, the
default -- a bounded, in-process LRU, not thread-safe by design, evicting by
`cache_max_size` rather than by time; `TranslationDiff::RedisCacheStore`,
built from `redis_url` when that is set, expiring entries after `cache_ttl`
and namespacing every key under `cache_namespace`; and
`TranslationDiff::ActiveRecordCacheStore`, opt-in, caching in the
application's own database -- see [SQL cache](sql-cache.md). Neither `redis`
nor `connection_pool` nor `redis-namespace` is a dependency of this gem --
`RedisCacheStore` takes anything answering to `#with` the way
`ConnectionPool` does, and yields anything `Redis::Namespace` accepts.

## `write_multi` is optional

A store need not implement `write_multi`. `SentenceCache#store` checks: a
store that answers to it gets one call carrying every translated sentence
from the batch; a store that does not is called once per sentence through
`write` instead, exactly as it always was. A custom cache store written
against the contract before `write_multi` existed keeps working unchanged
-- that is what "optional" means here.

All three shipped stores implement it: `MemoryCacheStore` loops over the
pairs (there is no round trip to save in-process); `RedisCacheStore`
pipelines the writes; `ActiveRecordCacheStore` upserts the whole batch in
one statement.

### The three write paths fail differently

Nobody had written this down before: what a partial failure leaves cached
depends on which of these shapes wrote it.

- **No `write_multi` (the per-key path), and `MemoryCacheStore`'s loop.**
  Sentences are written one at a time, in order. A failure at sentence N
  leaves 1..N-1 written, N failed, and N+1.. never attempted.
- **`RedisCacheStore#write_multi`.** A Redis pipeline is not a
  transaction: each `SETEX` in it runs independently of the others, so a
  failure in one does not stop its siblings from landing. Which of the
  batch actually landed does not follow the sentence order the way the
  per-key path's does.
- **`ActiveRecordCacheStore#write_multi`.** One `upsert_all` statement for
  the whole batch. It either lands as a whole or it does not -- there is no
  partial batch to reason about.

A caller that needs to know which sentences got cached after a failure
needs to know which of these three shapes wrote them; the answer is not the
same for all three.
