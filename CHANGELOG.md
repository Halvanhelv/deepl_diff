# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [3.1.0] - 2026-09-08

First release under the name **translation_diff**. This gem was published as
`deepl_diff` through 2.2.0.

There is no 3.0.0 entry. That version was tagged during the rename and then
held back before it reached RubyGems, so no `translation_diff` gem was ever
published as 3.0.0 and the tag names a commit that predates most of what is
described below. Everything here is relative to `deepl_diff` 2.2.0.

### Breaking

- Renamed the gem to `translation_diff` and the module to `TranslationDiff`.
- The provider (`config.provider`; see Removed below for what replaced the
  old `TranslationDiff.api` accessor) must satisfy the five-method contract
  (`translate`, optional `detect`, `max_request_size`, `max_batch_size`,
  `cache_key`) instead of being a raw client such as `DeepL`.
- `translate` takes keyword arguments -- `translate(values, from:, to:, **options)`
  -- and no longer accepts a positional options hash.
- Request-size and batch-size limits moved out of `Chunker` and into the
  provider (`#max_request_size`, `#max_batch_size`); they are no longer
  hard-coded to DeepL's numbers.
- **Every cache key changes.** The key now includes the provider's
  `cache_key`, a digest of the provider options, and lowercased language
  codes. Nothing cached by `deepl_diff` -- or by an earlier `translation_diff`
  prerelease -- is reused. The next translation of every sentence is a cache
  miss, once, everywhere.
- Dropped `punkt-segmenter` and, with it, its `unicode_utils` dependency.
  Sentence boundaries are now produced by `config.segmenter`,
  defaulting to `TranslationDiff::Segmenters::Pragmatic`, backed by the
  [`pragmatic_segmenter`](https://github.com/diasks2/pragmatic_segmenter) gem
  (MIT, zero dependencies of its own) -- so `ox` and `pragmatic_segmenter` are
  now the gem's only two runtime dependencies. Measured against the Golden
  Rules corpus -- the `context "Golden Rules" do` block of each of the 10
  per-language spec files on `diasks2/pragmatic_segmenter`, 80 exemplars in
  total; a sample of the same corpus is in
  `test/translation_diff/golden_rules_test.rb` -- the default now scores
  76/80 against punkt's 38/80 and the old in-house segmenter's 47/80; the
  gap is largest on languages with no letter case at all -- Arabic, Hindi,
  Armenian, Greek -- which the in-house segmenter cannot reason about by
  design.
- `config.segmenter_instance.split_offsets` now takes a second, optional
  `language:` keyword argument. `pragmatic_segmenter` picks its rule set by
  language and falls back to English rules without one, which can
  mis-segment other languages (Russian abbreviations, for one); `from:` is
  the only way a caller supplies it, and only when segmentation happens
  before language detection would need to run. `Segmenters::Pragmatic`
  normalises the code first -- downcased, region subtag dropped -- and falls
  back to English for anything `pragmatic_segmenter` does not recognise
  afterward. Without this, DeepL's own codes (`"RU"`, `"EN-GB"`) missed their
  rule set entirely: `pragmatic_segmenter`'s lookup is case-sensitive and
  region-blind, so this gem's own flagship provider was hitting the broken
  path on every call.
- **`config.rate_limit` now actually enforces the threshold you configure.**
  `TranslationDiff::RedisRateLimiter` called `Ratelimit#add(size)`, but that
  gem's signature is `add(subject, count = 1)` -- so it recorded the hit
  under a subject *named after the character count*, while `exceeded?`
  checked a subject nothing ever incremented. The limiter never limited
  anything, in every release back to `v1.0.2` (tagged 2023-02-16, roughly
  three years ago). If you have `rate_limit` configured, your traffic has
  never actually been throttled; on upgrading to 3.1.0 it will be, for the
  first time, against a threshold you set once and have never seen fire. You
  changed no configuration, but your throttling behaviour changes on
  upgrade. Re-validate `rate_limit` and `rate_interval` before upgrading --
  see "Rate limiting" in the README.
- `rate_interval` is silently clamped by the `ratelimit` gem's fixed bucket
  span to roughly **5-600 seconds** (measured: `3600` becomes `600`, `1`
  becomes `5`). Combined with a limiter that now actually fires, an interval
  configured above 600 seconds is enforced over 600 seconds instead -- up to
  six times more eager than the configuration reads. Keep `rate_interval`
  within that range, or expect a tighter effective window than configured.

### Removed

- The four module-level accessors (`TranslationDiff.api`, `.cache_store`,
  `.segmenter`, `.rate_limiter`) and `TranslationDiff::CACHE_NAMESPACE`.
  Every setting now lives on `TranslationDiff::Configuration`, reached
  through `TranslationDiff.config` or `TranslationDiff.configure`.

### Added

- A Google provider: `config.provider = :google` translates through Cloud
  Translation v2 (Basic), on the `google-cloud-translate-v2` gem, required
  lazily so an application using DeepL never needs it installed. It declares
  `google_api_key` and `google_project_id`; an API key alone is enough, and
  with none configured the gem reads `TRANSLATE_KEY`/`GOOGLE_CLOUD_KEY` or
  falls back to application default credentials. The provider asks for
  `format: :text` -- Google's own default HTML-escapes its output -- and
  downcases bare language codes so a configuration written for DeepL
  (`"EN"`) keeps working, leaving subtagged codes such as `"zh-Hans"` alone.
- `TranslationDiff::Configuration`, a declarative settings object built
  through the `option(key, default)` macro. Options fall back to their
  default until assigned, treat a blank string as unset, and support a
  callable default (evaluated on every read, not at load time). `#copy`
  carries option values into an isolated configuration without carrying
  already-built collaborators along with them.
- `TranslationDiff::Registry`, a small `name -> class` map backing every
  pluggable extension point: a registered class need only answer
  `build(config)`. Three registries exist: `TranslationDiff::Providers`,
  `TranslationDiff::Stores`, and `TranslationDiff::Segmenters.registry`.
- `TranslationDiff::Context`, returned by `TranslationDiff.context`: an
  isolated configuration scope with the same `#translate` entry point as the
  `TranslationDiff` module, for multi-tenant and per-request configuration
  that never touches the global configuration.
- Instrumentation and logging: `config.instrumenter` (anything satisfying
  `ActiveSupport::Notifications`' interface) receives `translate`, `cache`,
  `request` and `rate_limit` events, each named `<name>.translation_diff`
  and carrying counts, language codes and provider names only -- never the
  text being translated, its translation, or a credential. `config.logger`
  receives a `debug` line per provider resolution, naming the provider
  class, and is held to the same guarantee: it is never handed to
  `deepl-rb`, which logs the whole request -- auth header and payload -- at
  DEBUG when given a logger of its own. See "Instrumentation and logging" in
  the README for how to opt into that logging deliberately. Both are no-ops,
  at no extra cost, when left unset.
- `TranslationDiff::Providers.register` raises when a provider declares a
  `configuration_options` name another provider already declared. The two
  would otherwise share one accessor on `TranslationDiff::Configuration`, so
  a credential set for one service would be sent to the other. The same
  provider redeclaring its own options stays silent, so a double `require`
  and Rails development reloading keep working.
- `TranslationDiff::MemoryCacheStore`, a bounded, in-process LRU, and the
  new default cache store when `redis_url` is not configured -- so the
  library works before any infrastructure does.
- `TranslationDiff::Segmenters::Pragmatic`, the default sentence segmenter,
  wrapping `pragmatic_segmenter`'s per-language rule sets. Before
  segmenting, it shadows every single newline (one with no adjoining
  newline) to a space in a copy of the text -- `pragmatic_segmenter`
  otherwise treats almost any single newline as a sentence boundary
  candidate even with no punctuation at all, a false split that HTML text
  nodes routinely trigger via incidental source-formatting newlines -- then
  segments the shadow and recovers offsets against it, so the *original*
  text, newline included, reaches the output untouched. Blank-line runs
  (real paragraph breaks) are left alone. This costs one Golden Rules point
  (77 -> 76: a bare list of items separated by single newlines, with no
  punctuation, now segments as one unit instead of three) -- a deliberate
  trade, since that shape does not arise in this gem's actual input. It
  recovers offsets from the strings `pragmatic_segmenter` returns by locating
  each one in the shadow, in order, and keeps every offset it locates; the
  first sentence it cannot locate (`pragmatic_segmenter`'s cleaner also
  collapses runs of three or more spaces and respaces abbreviations such as
  `"Ph.D."`, among other things it rewrites) ends the search -- but the
  boundary at the end of the last sentence it did locate is not discarded
  with the rest, since it was matched character for character too; only the
  genuinely unrecoverable remainder becomes one final unit. This is a
  coarsening, not a failure -- every offset it ever emits has been verified,
  so the cache unit is simply larger, never wrong. It never guesses an
  offset it did not verify. `TranslationDiff::Segmenters::Pragmatic::Error`
  exists for the one case that would still be silent corruption -- offsets
  it computed itself violating their own postcondition (start at 0, strictly
  increase, stay within the text) -- not for ordinary `pragmatic_segmenter`
  rewriting.
- `TranslationDiff::Segmenters::Simple` (formerly `TranslationDiff::Segmenter`,
  renamed and moved to its own namespace alongside `Pragmatic`), the
  zero-dependency, in-house sentence segmenter this gem shipped with before
  `pragmatic_segmenter` became the default. It is deliberately conservative:
  it splits only on a handful of strong signals (a terminator followed by
  whitespace and an uppercase or CJK next character, none of the guard
  conditions -- a known abbreviation, an initial, digits on both sides, or a
  URL/email -- matching) so that a missed sentence boundary, which only
  costs a cache hit, is always preferred over a false one, which sends half
  a sentence to the translation provider. Its central rule has no meaning in
  scripts without letter case, which is why it is no longer the default; it
  stays available for callers who want no extra dependency and translate
  only from cased scripts. `config.segmenter` is swappable the same
  way `config.provider` and `.cache` are.
- `TranslationDiff::Providers::DeepL` and `TranslationDiff::Providers::Null`.
- `test/support/provider_contract.rb`, the executable form of the provider
  contract; any third-party provider can include it to verify it behaves as
  documented.
- `detect` is now its own provider method. Previously
  `api.translate(sample, nil, to)` returned an object of a different shape
  than the same call with `from:` given -- one method, two return types,
  told apart by an argument's value. A provider with no `detect` makes
  `from:` required and raises a clear error when it is missing, instead of
  `NoMethodError`.

### Changed

- `Adapters` renamed to `Providers`, and providers are now registered by
  name through `TranslationDiff::Providers.register` rather than assigned
  directly to a module accessor. A provider built through the registry is
  stamped with its registered name and needs no `cache_key` of its own; an
  object assigned straight to `config.provider`, bypassing the registry,
  must define `cache_key` itself or every call through it raises -- it has
  no registered name to fall back on.
- The cache key's options digest uses a canonical, version-stable encoding
  instead of `Hash#inspect`, which renders symbol-keyed hashes differently
  across Ruby 3.2-4.0.

### Fixed

- `TranslationDiff::RedisRateLimiter` requires `ratelimit` lazily, on the
  first check, and raises `TranslationDiff::Error` naming the gem to add
  when it is missing. Previously the bare constant surfaced a raw
  `NameError` instead of the message the Redis path already raises.

## [2.2.0] - 2026-09-07

Message-only release under the `deepl_diff` name. No code changes.

### Added

- `spec.post_install_message`, pointing installers at `translation_diff`,
  the gem's new name. `deepl_diff` 2.2.0 is the last release under that
  name and keeps working for anyone pinned to it.

## [2.1.0] - 2026-09-07

Six bugs found while auditing the library, each reproduced against the real
behaviour and covered by a regression test.

### Added

- `DeepLDiff::Request::Error`, raised when the adapter returns fewer
  translations than requested, instead of letting `nil` reach `Spacing` and
  fail two layers away as `NoMethodError`.

### Fixed

- The options hash passed to `Request` was consumed with `Hash#delete`, so a
  second call with the same hash -- or any frozen hash -- broke.
- The chunker compared raw `String#size` against a limit meant for the
  escaped request, so Cyrillic and other non-Latin text could run several
  times over the actual request-size limit.
- A detected source language (a `String`) was compared against `:to`
  (usually a `Symbol`) with `==`, so the same-language short circuit never
  fired and text was translated into its own language.
- Non-string scalars (`nil`, `Integer`, `Symbol`) raised instead of passing
  through untouched.
- The chunk count limit was off by one.

### Upgrade note

The chunker fix changes how non-Latin text is split into requests: chunks
are smaller, so there are more requests for the same number of characters
billed. A `MAX_CHUNK_SIZE` tuned empirically against Cyrillic now produces a
very different payload than it did.

## [2.0.0] - 2026-09-07

### Breaking

- Six unused or duck-typed runtime dependencies were dropped:
  `dry-initializer`, `connection_pool`, `redis`, `deepl-rb`,
  `redis-namespace`, `ratelimit`. Applications that relied on this gem to
  install them must now depend on them directly.
- `RedisRateLimiter` takes `threshold:` and `interval:` as keyword
  arguments.

### Fixed

- `RedisRateLimiter` declared `threshold` and `interval` as positional
  parameters, so the keyword call the README already documented silently
  discarded them and fell back to the defaults (8000 / 60).

## [1.1.1] - 2026-09-07

No changes to `lib/`.

### Changed

- The test suite moved from RSpec to Minitest.
- The gem is published from CI through RubyGems trusted publishing instead
  of a personal API key.

## [1.1.0] - 2026-09-07

### Changed

- Every runtime dependency is now explicitly versioned; the gem requires
  Ruby >= 3.2.
- CI moved from Travis to GitHub Actions, running against Ruby 3.2, 3.3,
  3.4 and 4.0, plus a RuboCop job.

### Fixed

- `cgi/escape`, `digest/md5`, `forwardable` and `stringio` are now required
  explicitly instead of relying on them being pulled in transitively.
- DeepL options were passed via `**options` into a method that takes a
  positional hash, so an empty options hash passed nothing.
- `Chunker::Chunk` members `values`/`size` were renamed (eventually to
  `texts`/`escaped_size`) because they shadowed `Struct#values` and
  `Struct#size`.

[3.1.0]: https://github.com/Halvanhelv/translation_diff/compare/v2.2.0...v3.1.0
[2.2.0]: https://github.com/Halvanhelv/deepl_diff/compare/v2.1.0...v2.2.0
[2.1.0]: https://github.com/Halvanhelv/deepl_diff/compare/v2.0.0...v2.1.0
[2.0.0]: https://github.com/Halvanhelv/deepl_diff/compare/v1.1.1...v2.0.0
[1.1.1]: https://github.com/Halvanhelv/deepl_diff/compare/v1.1.0...v1.1.1
[1.1.0]: https://github.com/Halvanhelv/deepl_diff/compare/v1.0.1...v1.1.0
