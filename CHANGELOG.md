# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [3.0.0] - 2026-09-07

First release under the name **translation_diff**. This gem was published as
`deepl_diff` through 2.2.0.

### Breaking

- Renamed the gem to `translation_diff` and the module to `TranslationDiff`.
- `TranslationDiff.api` must now be an adapter satisfying the five-method
  contract (`translate`, optional `detect`, `max_request_size`,
  `max_batch_size`, `cache_key`) instead of a raw client such as `DeepL`.
- `translate` takes keyword arguments -- `translate(values, from:, to:, **options)`
  -- and no longer accepts a positional options hash.
- Request-size and batch-size limits moved out of `Chunker` and into the
  adapter (`#max_request_size`, `#max_batch_size`); they are no longer
  hard-coded to DeepL's numbers.
- **Every cache key changes.** The key now includes the provider's
  `cache_key`, a digest of the provider options, and lowercased language
  codes. Nothing cached by `deepl_diff` -- or by an earlier `translation_diff`
  prerelease -- is reused. The next translation of every sentence is a cache
  miss, once, everywhere.
- Dropped `punkt-segmenter` and, with it, its `unicode_utils` dependency.
  Sentence boundaries are now produced by `TranslationDiff.segmenter`,
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
- `TranslationDiff.segmenter.split_offsets` now takes a second, optional
  `language:` keyword argument. `pragmatic_segmenter` picks its rule set by
  language and falls back to English rules without one, which can
  mis-segment other languages (Russian abbreviations, for one); `from:` is
  the only way a caller supplies it, and only when segmentation happens
  before language detection would need to run. `Segmenters::Pragmatic`
  normalises the code first -- downcased, region subtag dropped -- and falls
  back to English for anything `pragmatic_segmenter` does not recognise
  afterward. Without this, DeepL's own codes (`"RU"`, `"EN-GB"`) missed their
  rule set entirely: `pragmatic_segmenter`'s lookup is case-sensitive and
  region-blind, so this gem's own flagship adapter was hitting the broken
  path on every call.

### Added

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
  `"Ph.D."`, among other things it rewrites) ends the search, and the
  unrecoverable remainder of the text stands as one final unit. This is a
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
  only from cased scripts. `TranslationDiff.segmenter` is swappable the same
  way `TranslationDiff.api` and `.cache_store` are.
- `TranslationDiff::Adapters::DeepL` and `TranslationDiff::Adapters::Null`.
- `test/support/adapter_contract.rb`, the executable form of the adapter
  contract; any third-party adapter can include it to verify it behaves as
  documented.
- `detect` is now its own adapter method. Previously
  `api.translate(sample, nil, to)` returned an object of a different shape
  than the same call with `from:` given -- one method, two return types,
  told apart by an argument's value. An adapter with no `detect` makes
  `from:` required and raises a clear error when it is missing, instead of
  `NoMethodError`.

### Changed

- The cache key's options digest uses a canonical, version-stable encoding
  instead of `Hash#inspect`, which renders symbol-keyed hashes differently
  across Ruby 3.2-4.0.

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

[3.0.0]: https://github.com/Halvanhelv/translation_diff/compare/v2.2.0...v3.0.0
[2.2.0]: https://github.com/Halvanhelv/deepl_diff/compare/v2.1.0...v2.2.0
[2.1.0]: https://github.com/Halvanhelv/deepl_diff/compare/v2.0.0...v2.1.0
[2.0.0]: https://github.com/Halvanhelv/deepl_diff/compare/v1.1.1...v2.0.0
[1.1.1]: https://github.com/Halvanhelv/deepl_diff/compare/v1.1.0...v1.1.1
[1.1.0]: https://github.com/Halvanhelv/deepl_diff/compare/v1.0.1...v1.1.0
