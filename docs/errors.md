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
│                                                # TranslationDiff::Provider, or any
│                                                # provider -- registered or assigned --
│                                                # whose cache_key is blank
├── TranslationDiff::UnsupportedLanguageError   # the shipped language data doesn't list
│                                                # this source/target pair for this
│                                                # provider -- see docs/languages.md
├── TranslationDiff::Translator::Error          # from: missing and the provider cannot
│                                                # detect
├── TranslationDiff::Previewer::Error           # the same, asked of a preview: detecting
│                                                # a language is a paid request, and a
│                                                # preview never makes one
├── TranslationDiff::SentenceCache::Error       # provider options have no stable
│                                                # serialisation for the cache key
├── TranslationDiff::Batch::Error               # one sentence, once escaped, is larger
│                                                # than the provider's declared limit
├── TranslationDiff::Segmenters::Pragmatic::Error
│                                                # Pragmatic computed offsets that
│                                                # violate its own postcondition --
│                                                # not raised by ordinary use
├── TranslationDiff::RateLimiters::Redis::RateLimitExceeded
│                                                # the configured rate_limit was exceeded,
│                                                # raised by the Redis-backed limiter
└── TranslationDiff::RateLimiters::ActiveRecord::RateLimitExceeded
                                                 # the same condition, raised by the SQL-backed
                                                 # limiter -- a distinct class under its own
                                                 # namespace, not the class above. Rescuing
                                                 # `RateLimiters::Redis::RateLimitExceeded`
                                                 # specifically and switching `rate_limiter` to
                                                 # `:active_record` stops catching it; rescue
                                                 # `TranslationDiff::Error` to catch both.
```

Both `RateLimitExceeded` classes raise with a message naming the namespace,
the threshold and the interval that were exceeded (`"rate limit reached for
translation-diff: 8000 characters per 60 seconds"`) -- never the text that
tripped it.

Both SQL-backed collaborators report a database failure the same way. A
cache write that the database refuses -- including under Rails'
`prevent_writes` (a read-replica request, see
[Rails replica routing](sql-cache.md#rails-replica-routing)) -- is rescued,
redacted and swallowed, and the translation is returned anyway. The rate
limiter's own write raises a redacted `TranslationDiff::Error` instead of
continuing, because it runs before the provider does and a limiter that
cannot count is not a limiter. Either way `rescue TranslationDiff::Error`
around `translate` catches what a caller can catch, and no raw
`ActiveRecord::ReadOnlyError` reaches it.

`ProviderError` and its subclasses carry `#provider` (the registered name)
and `#status` (the HTTP status code), so a caller can log or branch on which
service and which response caused the failure without parsing the message.

`TranslationDiff::Registry` -- which backs the provider, cache store and
segmenter registries -- raises `TranslationDiff::Error` directly (not a
dedicated subclass) for an unknown name, listing what is actually
registered. `TranslationDiff::Batch::Error` is its own class rather than a
direct `TranslationDiff::Error`, so a caller can catch "this sentence is too
long for this provider" without also catching an unrelated registry miss; it
is raised when one sentence is larger once escaped than the provider's
declared `max_request_size` or `max_text_size` and so could never be sent
even in a batch of its own. The message names a short prefix of the
offending text and both numbers.

`ArgumentError`, not a `TranslationDiff::Error`, is what
`TranslationDiff.translate`, `TranslationDiff.preview` and their `Context`
counterparts raise when `to:` is missing or `nil`. It is a caller's mistake
before it is a translation, and the message names the keyword.

**Renamed in 3.1.0.** `TranslationDiff::Request::Error` is now
`TranslationDiff::Translator::Error` and `TranslationDiff::Cache::Error` is
now `TranslationDiff::SentenceCache::Error`; both classes they hung off are
gone. `TranslationDiff::Chunker::Error` is gone with no replacement -- the
condition it named now raises `TranslationDiff::Batch::Error`. A
`rescue TranslationDiff::Error` catches all three exactly as before.
