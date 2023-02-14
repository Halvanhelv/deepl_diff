# DeepLDiff

DeepL API wrapper helps to translate only changes between revisions of long texts.




**DeepLDiff** based on [GoogleTranslateDiff](https://github.com/gzigzigzeo/google_translate_diff)
## Use case

Assume your project contains a significant amount of products descriptions which:
- Require retranslation each time user edits them.
- Have a lot of equal parts (like return policy).
- Change frequently.

If your user changes a single word within the long description, you will be charged for the retranslation of the whole text.

Much better approach is to try to translate every repeated structural element (sentence) in your texts array just once to save money. This gem helps to make it done.

## Installation

Add this line to your application's Gemfile:

```ruby
gem 'deepl_diff'
```

And then execute:

    $ bundle

Or install it yourself as:

    $ gem install deepl_diff

## Usage

```ruby
require "deepl_diff"

# This dependencies are not included, as you might need to roll your own cache based on different store
require "redis"
require "connection_pool"
require "redis-namespace"
require "ratelimit" # Optional, if you will use

# Setup https://github.com/wikiti/deepl-rb
DeepL.configure do |config|
  config.auth_key = 'your-api-token'
  config.host = 'https://api-free.deepl.com' # Default value is 'https://api.deepl.com'
  config.version = 'v1' # Default value is 'v2'
end

# I always use pool for redis
pool = ConnectionPool.new(size: 10, timeout: 5) { Redis.new }

# Pass DeepL for DeepLDiff
DeepLDiff.api = DeepL

DeepLDiff.cache_store =
  DeepLDiff::RedisCacheStore.new(pool, timeout: 7.days, namespace: "t")

# Optional
DeepLDiff.rate_limiter =
  DeepLDiff::RedisRateLimiter.new(
    pool, threshold: 8000, interval: 60, namespace: "t"
  )

DeepLDiff.translate("test translations", from: "en", to: "es")
```

## How it works

- Text nodes are extracted from HTML.
- Every text node is split into sentences (using `punkt-segmenter` gem).
- Cache is checked for the presence of each sentence (using language couple and a hash of string).
- Missing sentences are translated via API and cached.
- Original HTML is recombined from translations and cache data.

*NOTE:* if `:from` is not specified or equal to nil, then the DeepL API will be called twice, the first time a sample of text up to 100 characters long will be transferred to determine the language, and the second time the entire text will be transferred.
        Try to specify `:from` explicitly

## Input

`::translate` can receive string, array or deep hash and will return the same, but translated.

```ruby
DeepLDiff.translate("test", from: "en", to: "es")
DeepLDiff.translate(%w[test language], from: "en", to: "es")
DeepLDiff.translate(
  { title: "test", values: { type: "frequent" } }, from: "en", to: "es"
)
```

See `DeepLDiff::Linearizer` for details.

## HTML

You can pass HTML as like as plain text:

```ruby
DeepLDiff.translate("<b>Black</b>", from: "en", to: "es")
```

## Very long texts

DeepL API has a limitation: query can not be longer than approximately 128 KB. If your text is really that long, multiple queries will be used to translate it automatically.

## Development

After checking out the repo, run `bin/setup` to install dependencies. Then, run `rake spec` to run the tests. You can also run `bin/console` for an interactive prompt that will allow you to experiment.

To install this gem onto your local machine, run `bundle exec rake install`. To release a new version, update the version number in `version.rb`, and then run `bundle exec rake release`, which will create a git tag for the version, push git commits and tags, and push the `.gem` file to [rubygems.org](https://rubygems.org).

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/wikiti/deepl-rb.
