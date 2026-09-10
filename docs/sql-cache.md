# SQL cache

## What it's for

If you already run Postgres or MySQL and do not want to stand up Redis for
one cache, `TranslationDiff::ActiveRecordCacheStore` caches translations in
the application's own database instead, and
`TranslationDiff::ActiveRecordRateLimiter` throttles requests there too.

Both are opt-in. Setting `redis_url` still means Redis, exactly as before --
nothing about an existing application's cache changes until you configure
one of these:

```ruby
TranslationDiff.configure do |config|
  config.cache = :active_record
  config.rate_limiter = :active_record
  config.cache_ttl = 30 * 24 * 60 * 60
end
```

## What this store is worse at than Redis

Two things, plainly. A read is a query against a table rather than an
`MGET` against an in-memory store. And the table grows until something
prunes it -- Redis expires a key for you; this store only stops serving an
expired row, it does not remove it by itself. See
[Pruning](#pruning-three-answers-none-imposed) below.

## The tables

Two tables, created by a migration you run once -- see
[The migration](#the-migration) below. This gem never creates or alters
either of them itself.

### `translation_diff_translations`

| Column | Meaning |
| --- | --- |
| `namespace` | `cache_namespace`. Two tenants share this table the way they share a Redis database; `#prune` only prunes its own configured namespace. |
| `key_digest` | `Digest::SHA256.hexdigest(key)` -- 64 characters, always. The cache key itself is not stored, only its digest: a variable-length unique index is the one thing guaranteed to bite somebody on MySQL. This also means an entry is not human-readable by its key -- to find one, compute the digest the same way and look that up. |
| `translation` | The cached value. |
| `expires_at` | What `cache_ttl` means in SQL. `nil` when `cache_ttl` is unset, which means the row never expires on its own. |
| `created_at`, `updated_at` | Standard ActiveRecord timestamps, set by `upsert_all`. |

Unique index on `[namespace, key_digest]` -- the second write of a key
replaces the first, which is the cache store contract. A separate index on
`expires_at` backs both the read (which filters on it) and `#prune` (which
deletes by it).

### `translation_diff_rate_limits`

| Column | Meaning |
| --- | --- |
| `namespace` | `cache_namespace`, same column, same meaning, same table-sharing as above. |
| `bucket` | A slice of time narrower than `rate_interval` -- see [The rate limiter](#the-rate-limiter) below for why. |
| `characters` | Characters counted into that bucket so far. |

Unique index on `[namespace, bucket]`, incremented by one guarded upsert
per check, so two processes hitting the same bucket cannot lose an
increment between them.

## The migration

`rails generate translation_diff:install` writes a timestamped migration
creating both tables, and lives under `lib/generators/`, loaded only when
Rails loads generators -- a non-Rails application never sees it and never
pays for it. **This gem never runs DDL itself:** the migration is the only
way either table comes into existence, and it is entirely yours to review,
edit, and run through your own deploy process.

For anyone not on Rails -- Sequel, plain ActiveRecord, a DBA who would
rather write the DDL directly -- here is that migration's body, verbatim
(the generator fills in the class's version bracket with your own
`ActiveRecord::Migration.current_version`; `7.1` below is this store's
floor, not a requirement to target that version specifically):

```ruby
class CreateTranslationDiffTables < ActiveRecord::Migration[7.1]
  def change
    create_table :translation_diff_translations do |t|
      t.string :namespace, null: false, limit: 64
      t.string :key_digest, null: false, limit: 64
      t.text :translation, null: false
      t.datetime :expires_at
      t.timestamps
    end

    add_index :translation_diff_translations, %i[namespace key_digest], unique: true,
              name: "index_translation_diff_translations_on_key"
    add_index :translation_diff_translations, :expires_at

    create_table :translation_diff_rate_limits do |t|
      t.string :namespace, null: false, limit: 64
      t.integer :bucket, null: false
      t.integer :characters, null: false, default: 0
    end

    add_index :translation_diff_rate_limits, %i[namespace bucket], unique: true,
              name: "index_translation_diff_rate_limits_on_bucket"
  end
end
```

Both tables are always created together -- there is no generator flag to
get one without the other, since deciding to use one but not the other
costs nothing at migration time.

## `cache_ttl` becomes `expires_at`

`cache_ttl` (in seconds, same option `RedisCacheStore` reads) is written
into each row's `expires_at` at write time. A row past `expires_at` is
never read, whether or not anything has deleted it yet -- expiry and
deletion are two different questions here, unlike Redis, where a `SETEX`
key simply stops existing.

## Pruning: three answers, none imposed

Deleting an expired row is a separate question from whether it is served,
and there is no single right answer to "when," so none is forced on you:

- **`rake translation_diff:prune`.** Calls `#prune` on the configured cache
  store and, separately, on the configured rate limiter -- deleting rows
  and buckets past their expiry, each in its own configured namespace. Wire
  it into cron, a scheduled job, whatever your host already runs. Either
  side that does not support pruning (`:redis`, or an object of your own)
  is reported and skipped rather than failing the task.
- **`config.cache_prune_probability`** (default `0.0`, off). A fraction
  between 0 and 1: on a write, `ActiveRecordCacheStore` rolls under it and
  prunes if it wins. Off by default, because a translation-serving request
  should not be paying, even occasionally, for someone else's expired rows.
- **Doing nothing.** Also a supported answer. An unpruned table is correct
  -- reads still skip every expired row -- just larger than it needs to be.

`#prune` only ever deletes rows in its own configured `cache_namespace`; a
multi-tenant table with several namespaces needs `#prune` called once per
namespace if every tenant is to be pruned.

## `active_record_base`: a second database, or a reader/writer role

`config.active_record_base` (default `::ActiveRecord::Base`) is the class
`ActiveRecordCacheStore` and `ActiveRecordRateLimiter` build their model
from. Point it at a class connected to a second database, or one pinned to
a writer role, and this store's traffic follows that connection instead of
your application's primary one:

```ruby
class TranslationDiffRecord < ActiveRecord::Base
  self.abstract_class = true
  connects_to database: { writing: :translation_diff, reading: :translation_diff }
end

TranslationDiff.configure do |config|
  config.cache = :active_record
  config.active_record_base = TranslationDiffRecord
end
```

## The ActiveRecord version floor

**ActiveRecord 7.1 or newer.** `upsert_all` needs `unique_by` on Postgres
and SQLite, and `record_timestamps:` only landed in 7.1. An older version is
refused by name, at the point the store is first used, rather than failing
inside a query with a message that does not say why:

```
the ActiveRecord cache store needs ActiveRecord 7.1 or newer (found 7.0.0):
upsert_all takes unique_by and record_timestamps there.
```

`activerecord` is never a dependency of this gem -- neither in the gemspec
nor required at load time. `ActiveRecordCacheStore#model` and
`ActiveRecordRateLimiter#model` `require "active_record"` on first use, so
an application that never configures `:active_record` never loads it, the
same way `RedisCacheStore` only reaches for `redis` when `redis_url` is
set. Add `gem "activerecord"` (and a database adapter) to your own Gemfile
to use either.

## `write_multi`

Both `ActiveRecordCacheStore` and `RedisCacheStore` implement the cache
store contract's optional `write_multi(pairs)` -- see
[`write_multi` is optional](caching.md#write_multi-is-optional) for what
that means, and
[The two write paths fail differently](caching.md#the-two-write-paths-fail-differently)
for how a batch write fails differently from a per-key one.
`ActiveRecordCacheStore#write_multi` is a single `upsert_all` for the whole
batch: a forty-sentence paragraph is one statement, not forty.

## The rate limiter

`config.rate_limiter = :active_record` throttles the same way `rate_limit`
and `rate_interval` already configure the Redis-backed limiter, but counts
characters into `translation_diff_rate_limits` instead of Redis.

The window is sliding, not tumbling. Time is divided into buckets a
fraction of `rate_interval` wide, not one bucket per interval, and a check
sums every bucket covering the trailing `rate_interval` seconds before
deciding whether the threshold is exceeded -- so the answer does not jump
the moment a single wide bucket rolls over, the way it would if the whole
interval were one bucket. Like the check it replaces, it looks at the
total *before* adding the new characters, so a check that itself pushes the
total over the threshold still succeeds; the next one raises.

This is still approximate at a window boundary, the same way the
`ratelimit` gem this store does not depend on is. A translation throttle
exists to keep a provider's quota from being exceeded, not to be a billing
meter.

`#prune` here deletes buckets that have fully aged out of the window, in
the configured namespace. `rake translation_diff:prune` calls it the same
way it calls the cache store's `#prune`. There is no
`cache_prune_probability` equivalent for the rate limiter -- the rake task,
or leaving old buckets in place, are the two supported answers here.
