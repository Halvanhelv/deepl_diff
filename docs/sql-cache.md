# SQL cache

## What it's for

If you already run Postgres or MySQL and do not want to stand up Redis for
one cache, `TranslationDiff::Stores::ActiveRecord` caches translations in
the application's own database instead, and
`TranslationDiff::RateLimiters::ActiveRecord` throttles requests there too.
Supported means exercised in CI: the suite runs against Postgres, MySQL
and SQLite on every push.

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

## Transactions

A write joins the caller's transaction. A failed write no longer poisons
it -- the write runs in its own savepoint, so an `ActiveRecord::ActiveRecordError`
there does not abort a transaction it does not own -- but the rollback
semantics otherwise stay ordinary: if the caller's transaction rolls back, a
translation this store just wrote rolls back with it, and the next request
pays for it again. This is the largest difference between this store and
the Redis one it substitutes for -- a Redis write is never inside anyone's
transaction, so it never rolls back with one.

That savepoint failure never reaches a caller of `TranslationDiff.translate`
either, whatever raised it -- see
[The three write paths fail differently](caching.md#the-three-write-paths-fail-differently).

## What ends up in your log

`upsert_all` inlines values into the SQL it sends rather than binding them,
so a written translation appears verbatim in the host application's own
ActiveRecord log at `debug` level. That is a separate claim from the one in
[Configuration](configuration.md): this gem's own `logger` option never
prints content, but that says nothing about the application's own SQL log,
which sees the statement ActiveRecord actually sent. A failed write is
scrubbed -- the `TranslationDiff::Error` it raises carries the adapter's
error class, never the row, and its cause chain is severed so the original
exception cannot carry the row into an error tracker either, see
[`write_multi`](#write_multi) -- but a successful one is not; nothing here redacts your debug-level query log. If
your application logs SQL at `debug` and what it translates is
confidential, keep that log above `debug` around this store, or use
`Stores::Redis` instead.

That scrubbing covers every `ActiveRecord::ActiveRecordError` the write path
can raise, not just a syntax or constraint failure -- see
[Rails replica routing](#rails-replica-routing) below for the error this
widened scope was written for.

## The tables

Two tables, created by a migration you run once -- see
[The migration](#the-migration) below. This gem never creates or alters
either of them itself.

### `translation_diff_translations`

| Column | Meaning |
| --- | --- |
| `namespace` | `cache_namespace`. Two tenants share this table the way they share a Redis database; `#prune` only prunes its own configured namespace. Limited to 64 characters, the column's own limit; `config.cache_namespace =` refuses a longer value at `configure` time rather than at the first write. |
| `key_digest` | `Digest::SHA256.hexdigest(key)` -- 64 characters, always. The cache key itself is not stored, only its digest: a variable-length unique index is the one thing guaranteed to bite somebody on MySQL. This also means an entry is not human-readable by its key -- to find one, compute the digest the same way and look that up. |
| `translation` | The cached value. |
| `expires_at` | What `cache_ttl` means in SQL. `nil` when `cache_ttl` is unset, or set to `nil` or anything non-positive, which all mean the row never expires on its own. |
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
    create_table :translation_diff_translations, if_not_exists: true do |t|
      t.string :namespace, null: false, limit: 64
      t.string :key_digest, null: false, limit: 64
      t.text :translation, null: false, limit: 16_777_215
      t.datetime :expires_at
      t.timestamps
    end

    add_index :translation_diff_translations, %i[namespace key_digest], unique: true,
              name: "index_translation_diff_translations_on_key", if_not_exists: true
    add_index :translation_diff_translations, :expires_at, if_not_exists: true

    create_table :translation_diff_rate_limits, if_not_exists: true do |t|
      t.string :namespace, null: false, limit: 64
      t.bigint :bucket, null: false
      t.integer :characters, null: false, default: 0
    end

    add_index :translation_diff_rate_limits, %i[namespace bucket], unique: true,
              name: "index_translation_diff_rate_limits_on_bucket", if_not_exists: true
  end
end
```

Every `create_table` and `add_index` above carries `if_not_exists: true`, so
a DBA can run this migration twice without the second run failing. `bucket`
is a `bigint`, not the plain 4-byte integer it looks like it could be: at
`bucket_width` 1 second -- what `rate_interval` under 24 seconds folds to,
see [The rate limiter](#the-rate-limiter) below -- `bucket` is the raw Unix
timestamp, and a 4-byte integer column holding that overflows in January
2038 the same way a 32-bit `time_t` does.

Both tables are always created together -- there is no generator flag to
get one without the other, since deciding to use one but not the other
costs nothing at migration time.

`translation` carries `limit: 16_777_215`, which is a no-op on Postgres and
SQLite -- `text` there has no length ceiling regardless -- and yields
`MEDIUMTEXT` on MySQL instead of the default `TEXT`, which tops out at
65,535 bytes. Without it, one sentence over that size failed the whole
batch it rode in with on MySQL, and PostgreSQL and SQLite were never
affected.

**An existing MySQL installation** that ran this migration before it
carried the `limit:` needs one statement, once, through its own deploy
process -- this gem still never runs DDL for you:

```sql
ALTER TABLE translation_diff_translations MODIFY translation MEDIUMTEXT NOT NULL;
```

Postgres and SQLite users have nothing to do here.

## `cache_ttl` becomes `expires_at`

`cache_ttl` (in seconds, same option `Stores::Redis` reads) is written
into each row's `expires_at` at write time. A row past `expires_at` is
never read, whether or not anything has deleted it yet -- expiry and
deletion are two different questions here, unlike Redis, where a `SETEX`
key simply stops existing.

A non-positive `cache_ttl` -- `0`, a negative number, or `nil` -- means
never expires: `expires_at` is written as `nil`, and a `nil` `expires_at`
is what "never expires on its own" means in the table above. All three
values fold to that one `nil` in `TranslationDiff.configure` itself, so
`config.cache_ttl` reads back `nil` for any of them, not just the one you
set.

## Pruning: three answers, none imposed

Deleting an expired row is a separate question from whether it is served,
and there is no single right answer to "when," so none is forced on you:

- **`rake translation_diff:prune`.** Calls `#prune` on the configured cache
  store and, separately, on the configured rate limiter -- deleting rows
  and buckets past their expiry, each in its own configured namespace. Wire
  it into cron, a scheduled job, whatever your host already runs. Either
  side that does not support pruning (`:redis`, or an object of your own)
  is reported and skipped rather than failing the task.

  The task ships inside this gem, under `lib/translation_diff/tasks/`, not
  in the dev Rakefile -- a dependency's own Rakefile is never loaded by a
  host application's `rake`. On Rails, a `Railtie` wires it into the
  application's own rake tasks automatically, enhanced to depend on the
  `:environment` task so it runs against the application's own
  configuration rather than a default one -- `rake -T` shows it with no
  extra setup. Off Rails, nothing registers it automatically: `load` the
  file yourself (from wherever the gem is installed) to add it to your own
  `Rakefile`, and note that it does **not** get an
  `:environment`-equivalent dependency there -- your own bootstrap needs to
  configure `TranslationDiff` before the task runs, the same way it would
  before any code that calls `translate`. A cron entry that prunes
  silently against the wrong (or unconfigured) configuration is worse than
  no pruning at all.
- **`config.cache_prune_probability`** (default `0.0`, off). A fraction
  between 0 and 1: on a write, `Stores::ActiveRecord` rolls under it and
  prunes if it wins, in a savepoint of its own so a failed prune cannot
  abort a transaction the caller opened. A value outside `0.0..1.0`, or one
  that is not a number, is refused at `configure` time. Off by default,
  because a translation-serving request
  should not be paying, even occasionally, for someone else's expired rows.
  A value that will not coerce to a number is refused at `configure` time,
  not on the first write that would have consulted it. A prune that fails
  here fails exactly like a failed write, and is rescued the same way -- it
  does not lose the translation it rode in with, see
  [The three write paths fail differently](caching.md#the-three-write-paths-fail-differently).
- **Doing nothing.** Also a supported answer. An unpruned table is correct
  -- reads still skip every expired row -- just larger than it needs to be.

`#prune` only ever deletes rows in its own configured `cache_namespace`; a
multi-tenant table with several namespaces needs `#prune` called once per
namespace if every tenant is to be pruned.

## `active_record_base`: a second database

`config.active_record_base` (default `::ActiveRecord::Base`) is the class
`Stores::ActiveRecord` and `RateLimiters::ActiveRecord` build their model
from. Point it at a class connected to a second database and this store's
traffic follows that connection instead of your application's primary one:

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

**This is not a way around a read-replica decision Rails already made for
the request.** See [Rails replica routing](#rails-replica-routing) below --
`active_record_base` still matters, but not for that.

## Rails replica routing

If your application routes GET requests to a read replica the way the Rails
guides describe -- `ActiveRecord::Middleware::DatabaseSelector` in the
middleware stack -- every GET runs with `prevent_writes` on. A page that
calls `translate` and triggers a cache or rate-limit write during that
request hits `ActiveRecord::ReadOnlyError`.

Pointing `active_record_base` at a class connected to its own writer role,
or at an entirely separate database, does **not** avoid this. `prevent_writes`
is enforced by the connection handler for the request as a whole, not per
model or per connection: verified against a live Rails application,
pointing `active_record_base` at the application's own writer-role class,
and separately at a wholly unrelated MySQL database, both still raised
`ActiveRecord::ReadOnlyError` on the write. `active_record_base` changes
which database this store's traffic goes to; it does not change whether
Rails currently permits writes at all.

For the cache write specifically, the error is redacted -- see
[What ends up in your log](#what-ends-up-in-your-log) -- and it does not
reach your call to `translate` as an exception: the translator rescues it,
logs it, fires a `cache_error` instrumentation event (provider and error
class only, never content -- see [Instrumentation](instrumentation.md)),
and returns the translation anyway. What does not happen is the write: a
translation served on a GET beneath this middleware is not cached by this
store, for that request.

**The rate limiter fails differently, because it runs earlier.** If
`config.rate_limiter = :active_record` and the same request hits it,
`RateLimiters::ActiveRecord#check` cannot record what it is about to allow, so
it raises `TranslationDiff::Error` naming the adapter's error class -- and
because the check runs before the provider is ever called, the `translate`
call fails outright rather than degrading. Nothing has been paid for at
that point, which is why this one refuses instead of continuing: a limiter
that cannot count is not a limiter, and quietly translating past it is how
an application loses its provider account.

Two things actually avoid both failures, both checked directly against a
Rails application with `DatabaseSelector` configured:

- **Translate somewhere `DatabaseSelector` is not wrapping.** A background
  job, a POST action, a console session -- anywhere outside a GET this
  middleware routes, there is no `prevent_writes` in effect to begin with.
- **Wrap the call to permit writes for its duration:**
  ```ruby
  ActiveRecord::Base.connected_to(role: :writing) do
    TranslationDiff.translate(text, from: "en", to: "es")
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
nor required at load time. `Stores::ActiveRecord#model` and
`RateLimiters::ActiveRecord#model` `require "active_record"` on first use, so
an application that never configures `:active_record` never loads it, the
same way `Stores::Redis` only reaches for `redis` when `redis_url` is
set. Add `gem "activerecord"` (and a database adapter) to your own Gemfile
to use either.

## `write_multi`

Both `Stores::ActiveRecord` and `Stores::Redis` implement the cache
store contract's optional `write_multi(pairs)` -- see
[`write_multi` is optional](caching.md#write_multi-is-optional) for what
that means, and
[The three write paths fail differently](caching.md#the-three-write-paths-fail-differently)
for how a batch write fails differently from a per-key one.
`Stores::ActiveRecord#write_multi` is a single `upsert_all` for the whole
batch: a forty-sentence paragraph is one statement, not forty.

## The rate limiter

`config.rate_limiter = :active_record` throttles the same way `rate_limit`
and `rate_interval` already configure the Redis-backed limiter, but counts
characters into `translation_diff_rate_limits` instead of Redis.

The window is sliding, not tumbling. Time is divided into buckets
`rate_interval / 12` seconds wide (never narrower than 1 second), not one
bucket per interval, and a check sums every bucket touching the trailing
`rate_interval` seconds before deciding whether the threshold is exceeded
-- so the answer does not jump the moment a single wide bucket rolls over,
the way it would if the whole interval were one bucket. Like the check it
replaces, it looks at the total *before* adding the new characters, so a
check that itself pushes the total over the threshold still succeeds; the
next one raises.

The oldest bucket summed is only ever partially inside the window, and it
is summed in full anyway rather than pro-rated, which errs toward
stricter. So the window actually enforced is `rate_interval` to
`rate_interval + rate_interval / 12` seconds (that upper bound is one
bucket width, floored at 1 second) -- slightly stricter than what was
configured, never looser. A translation throttle exists to keep a
provider's quota from being exceeded, not to be a billing meter, so this
was left as the simpler, safer direction to be wrong in rather than made
exact.

`#prune` here deletes buckets that have fully aged out of the window, in
the configured namespace. `rake translation_diff:prune` calls it the same
way it calls the cache store's `#prune`. There is no
`cache_prune_probability` equivalent for the rate limiter -- the rake task,
or leaving old buckets in place, are the two supported answers here.
