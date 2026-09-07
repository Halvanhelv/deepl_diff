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

### Added

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
