# Errors

Every error this gem raises inherits from `TranslationDiff::Error < StandardError`,
so rescuing the gem's failures in one clause is a single `rescue TranslationDiff::Error`:

```
TranslationDiff::Error
├── TranslationDiff::ConfigurationError         # a provider is missing a required option
├── TranslationDiff::ProviderError              # the service answered and said no
│   ├── AuthenticationError                     # 401/403
│   ├── RateLimitError                          # 429, once faraday-retry's own retries
│   │                                            # are exhausted -- carries #retry_after
│   │                                            # when the service sent one
│   ├── QuotaExceededError                      # 456
│   ├── InvalidRequestError                     # any other 4xx
│   └── ServiceError                            # 5xx, or anything else
├── TranslationDiff::TransportError             # nobody answered: connection failed,
│                                                # timed out, or TLS failed
├── TranslationDiff::ResponseError              # the answer was well-formed HTTP but broke
│                                                # this library's contract -- a body that
│                                                # is not JSON, a provider that returned
│                                                # the wrong number of translations, or one
│                                                # that returned no translation for an input
├── TranslationDiff::InvalidProviderError       # a class registered without inheriting
│                                                # TranslationDiff::Provider
├── TranslationDiff::Translator::Error          # from: missing and the provider cannot
│                                                # detect, cache_key missing on an
│                                                # assigned provider object
├── TranslationDiff::SentenceCache::Error       # provider options have no stable
│                                                # serialisation for the cache key
├── TranslationDiff::Segmenters::Pragmatic::Error
│                                                # Pragmatic computed offsets that
│                                                # violate its own postcondition --
│                                                # not raised by ordinary use
└── TranslationDiff::RedisRateLimiter::RateLimitExceeded
                                                 # the configured rate_limit was exceeded
```

`ProviderError` and its subclasses carry `#provider` (the registered name)
and `#status` (the HTTP status code), so a caller can log or branch on which
service and which response caused the failure without parsing the message.

`TranslationDiff::Registry` -- which backs the provider, cache store and
segmenter registries -- also raises `TranslationDiff::Error` directly (not a
dedicated subclass) for an unknown name, listing what is actually
registered. So does `TranslationDiff::Batch`, when one sentence is larger
once escaped than the provider's declared `max_request_size` or
`max_text_size` and so could never be sent even in a batch of its own; the
message names a short prefix of the offending text and both numbers.

`ArgumentError`, not a `TranslationDiff::Error`, is what
`TranslationDiff.translate` and `Context#translate` raise when `to:` is
missing or `nil`. It is a caller's mistake before it is a translation, and
the message names the keyword.

**Renamed in 3.1.0.** `TranslationDiff::Request::Error` is now
`TranslationDiff::Translator::Error` and `TranslationDiff::Cache::Error` is
now `TranslationDiff::SentenceCache::Error`; both classes they hung off are
gone. `TranslationDiff::Chunker::Error` is gone with no replacement -- the
condition it named now raises `TranslationDiff::Error` from `Batch`. A
`rescue TranslationDiff::Error` catches all three exactly as before.
