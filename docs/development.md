# Former name, upgrading, and development

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
[The rate limiter contract](contracts.md#the-rate-limiter-contract): the limiter was
never actually enforcing your threshold before 3.1.0, and it starts doing so
now. See [CHANGELOG.md](../CHANGELOG.md) for the full list of breaking changes.

**If you registered a custom provider,** it must now subclass
`TranslationDiff::Provider` (or `TranslationDiff::HTTPProvider`), declare
`self.capabilities`, and implement `#translate(request)` taking a
`TranslationDiff::Translation::Request` and returning a
`TranslationDiff::Translation::Response` -- the duck-typed
`#translate(texts, from:, to:, **options)` plus `#max_request_size` and
`#max_batch_size` methods are no longer read at all. See [Writing a
provider](providers.md#writing-a-provider).

## Development

After checking out the repo, run `bin/setup` to install dependencies. Then, run `rake test` to run the tests. You can also run `bin/console` for an interactive prompt that will allow you to experiment.

To install this gem onto your local machine, run `bundle exec rake install`. To release a new version, update the version number in `version.rb`, and then run `bundle exec rake release`, which will create a git tag for the version, push git commits and tags, and push the `.gem` file to [rubygems.org](https://rubygems.org).
