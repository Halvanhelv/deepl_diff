# Instrumentation and logging

`config.instrumenter` accepts anything satisfying
`ActiveSupport::Notifications`' interface -- `#instrument(name, payload) { }` --
and `config.logger` accepts a standard `Logger`. Neither is required: with
both unset, `TranslationDiff.translate` runs exactly the same, at no extra
cost.

A translation emits up to four events, each named `<name>.translation_diff`:

| Event | Fired | Payload |
| --- | --- | --- |
| `translate` | Once per `translate` call that reaches the provider, wrapping the whole thing. A call whose source and target languages are the same, or whose values hold no translatable text at all, returns early and emits no events. | `from`, `to`, `provider`, `values` (number of texts) |
| `cache` | Once per chunk, after checking the cache. | `provider`, `hits`, `misses` |
| `request` | Once per chunk actually sent to the provider (skipped entirely on a full cache hit). | `provider`, `batch` (values sent), `characters` |
| `rate_limit` | Once per chunk sent to the provider, only when a rate limiter is configured. | `provider`, `characters` |

**Instrumentation payloads never contain the text being translated, its
translation, or a credential.** This is a guarantee, not an implementation
detail: this library handles other people's content, and an instrumenter
usually writes somewhere that content must not go. Only counts, language
codes and provider names cross that boundary.

`config.logger` receives one `debug` line per provider resolution, naming
the provider class in use -- nothing about the content being translated. The
same guarantee applies to it as to instrumentation payloads: no log line this
library writes carries the text being translated, its translation, or a
credential.

**No HTTP-backed provider ever receives `config.logger`, and there is no way
to opt one in.** `TranslationDiff::HTTPProvider` installs no logging
middleware on its Faraday connection and never passes a logger to it -- this
is enforced by `test/support/http_provider_contract.rb`, not merely
documented. Earlier versions wrapped `deepl-rb`, which logged a
`Request details:` line at DEBUG holding the full
`Authorization: DeepL-Auth-Key ...` header and the request payload -- your
API key and the text being translated -- if you gave it a logger of its own.
Owning the transport directly closed that door rather than working around
it: nothing this library builds writes source text, a translation, or a
credential anywhere, and no configuration option reopens that.
