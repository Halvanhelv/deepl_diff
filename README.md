# TranslationDiff

A translation cache that helps translate only changes between revisions of long texts.

**TranslationDiff** based on [GoogleTranslateDiff](https://github.com/gzigzigzeo/google_translate_diff)

## Why TranslationDiff?

Assume your project contains a significant amount of products descriptions which:
- Require retranslation each time user edits them.
- Have a lot of equal parts (like return policy).
- Change frequently.

If your user changes a single word within the long description, you will be charged for the retranslation of the whole text.

Much better approach is to try to translate every repeated structural element (sentence) in your texts array just once to save money. This gem helps to make it done.

## Show me the code

```ruby
# The simplest translation
TranslationDiff.configure do |config|
  config.deepl_api_key = ENV["DEEPL_API_KEY"]
  config.redis_url = ENV["REDIS_URL"]
end

TranslationDiff.translate("Привет.", from: "ru", to: "en")
```

```ruby
# Nested structures come back the same shape
TranslationDiff.translate("test", from: "en", to: "es")
TranslationDiff.translate(%w[test language], from: "en", to: "es")
TranslationDiff.translate(
  { title: "test", values: { type: "frequent" } }, from: "en", to: "es"
)
```

```ruby
# HTML markup is preserved
TranslationDiff.translate("<b>Black</b>", from: "en", to: "es")
```

```ruby
# class="notranslate" marks a span to protect (provider support varies -- see the caveats below)
TranslationDiff.translate(
  '<span class="notranslate">Bold Mountain</span> is a good place.', from: "en", to: "ru"
)
```

```ruby
# Switch provider for one call, without touching the global configuration
TranslationDiff.translate(blog_post, from: "en", to: "de", provider: :google)
```

```ruby
# Any keyword other than from:, to:, provider: and config: is forwarded to the provider
TranslationDiff.translate(contract, from: "en", to: "de", formality: :more)
```

```ruby
# An isolated context for its own configuration -- global config.deepl_api_key stays untouched
formal = TranslationDiff.context do |config|
  config.provider = :deepl
  config.deepl_api_key = ENV["DEEPL_AUTH_KEY"]
end
formal.translate(contract, from: "en", to: "de", formality: :more)
```

```ruby
# Redis-backed cache, shared across processes
TranslationDiff.configure { |config| config.redis_url = ENV["REDIS_URL"] }
```

```ruby
# A rate limit, in characters per interval
TranslationDiff.configure { |config| config.rate_limit = 100_000 }
```

```ruby
# Instrumentation, through anything satisfying the ActiveSupport::Notifications interface
TranslationDiff.configure { |config| config.instrumenter = ActiveSupport::Notifications }
```

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

**Amazon:** translates one text per call (no batch form of `TranslateText`) and has no HTML mode, so `notranslate` is not honoured.

**LibreTranslate:** preserves markup but does not honour `notranslate` either -- measured against a real instance, not assumed.

See [Providers](docs/providers.md) for configuring each one, the full capabilities explanation, and writing your own.

## Features

- **Content-hash caching:** a small edit to a long document is billed for the edit, not the whole document
- **Six built-in providers** -- DeepL, Google Cloud Translation, Azure AI Translator, ModernMT, LibreTranslate, Amazon Translate -- or bring your own by subclassing a small base class
- **HTML aware:** markup is preserved, and `class="notranslate"` can protect a span (provider support varies -- see the caveats below)
- **Any shape:** strings, arrays, and deep hashes go in and come back translated in the same shape
- **Two cache stores:** `MemoryCacheStore` out of the box, `RedisCacheStore` once you configure `redis_url`
- **Isolated contexts:** `TranslationDiff.context` for multi-tenant apps and per-request provider overrides, without touching the global configuration
- **Pluggable sentence segmenter:** `pragmatic_segmenter` by default, with a zero-dependency `Simple` alternative
- **HTTP retries, timeouts, and backoff** on every REST-backed provider, via `faraday` and `faraday-retry`
- **One error hierarchy** under `TranslationDiff::Error`, carrying the provider name and HTTP status
- **Optional rate limiting and instrumentation** -- credentials and translated content never appear in a log line

## Installation

Ruby 3.4 or newer is required.

Add this line to your application's Gemfile:

```ruby
gem 'translation_diff'
```

And then execute:

    $ bundle

Or install it yourself as:

    $ gem install translation_diff

This gem loads `ox`, `pragmatic_segmenter`, `faraday`, and `faraday-retry` at require time. `aws-sigv4`, `redis`, `connection_pool`, `redis-namespace`, and `ratelimit` are yours to add, only if you use the feature that needs them -- see [Dependencies](docs/configuration.md#dependencies).

## Documentation

[Configuration](docs/configuration.md) · [Providers](docs/providers.md) · [Caching](docs/caching.md) · [Contracts](docs/contracts.md) · [Instrumentation](docs/instrumentation.md) · [Errors](docs/errors.md) · [How it works](docs/how-it-works.md) · [Upgrading & development](docs/development.md)

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/Halvanhelv/translation_diff.

## License

Released under the [MIT License](LICENSE.txt).
