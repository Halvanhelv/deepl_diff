# Instrumentation and logging

`config.instrumenter` accepts anything satisfying
`ActiveSupport::Notifications`' interface -- `#instrument(name, payload) { }` --
and `config.logger` accepts a standard `Logger`. Neither is required: with
both unset, `TranslationDiff.translate` runs exactly the same, at no extra
cost.

A translation emits up to six events, each named `<name>.translation_diff`:

| Event | Fired | Payload |
| --- | --- | --- |
| `translate` | Once per `translate` call that reaches the provider, wrapping the whole thing. A call whose source and target languages are the same, or whose values hold no translatable text at all, returns early and emits no events. | `from`, `to`, `provider`, `values` (number of texts) |
| `cache` | Once per `translate` call that reaches the provider, after checking the cache for every sentence at once. | `provider`, `hits`, `misses` |
| `request` | Once per batch actually sent to the provider (skipped entirely on a full cache hit). | `provider`, `batch` (values sent), `characters` |
| `rate_limit` | Once per batch sent to the provider, only when a rate limiter is configured. | `provider`, `characters` |
| `usage` | Once per batch actually sent to the provider, right after `request`. | `provider`, `characters`, `billed_characters`, `reported`, `model` |
| `cache_error` | Only when writing the translation back to the cache fails -- after the provider has already answered. Never fires on a successful write, so it is not part of every call the way the other five are. | `provider`, `error` (the failed write's error class, as a string) |

`cache_error` is what a failing cache write looks like from the outside:
the write itself is rescued, not the translation, which still reaches the
caller -- see
[The three write paths fail differently](caching.md#the-three-write-paths-fail-differently).
`error` is the exception's class name (`"ActiveRecord::ReadOnlyError"`,
`"Redis::CannotConnectError"`, ...), never its message, which could echo
the row it failed to write.

`usage`'s `characters` is what this library sent, counted locally -- the same
number `request` carries. `billed_characters` is what the provider said it
charged for, or `nil` when it said nothing. **`reported` means the provider
reports billing at all -- not that this particular response was billed.**
`billed_characters: nil` alone cannot tell "this provider never says" apart
from "this response omitted it"; `reported` is what makes the `nil` honest.
Summing `billed_characters` across providers without checking `reported`
first produces a total that is quietly too low, since only three of the six
built-in providers (DeepL, Azure, ModernMT) report billing at all -- the
other three always answer `nil`. `model` is the model the provider used,
when it names one, and `nil` otherwise.

**`cache` fires once per call as of 3.1.0, not once per chunk.** The cache is
now consulted for every sentence in one `read_multi` before anything is
batched, so there is one event where there used to be one per chunk. `hits`
and `misses` still sum to the same totals over a call, so a counter that adds
them up is unaffected; a counter of *events*, or a histogram of per-chunk hit
ratios, will see the cardinality drop.

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
