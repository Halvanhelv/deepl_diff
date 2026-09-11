# Instrumentation and logging

`config.instrumenter` accepts anything satisfying
`ActiveSupport::Notifications`' interface -- `#instrument(name, payload) { }` --
and `config.logger` accepts a standard `Logger`. Neither is required: with
both unset, `TranslationDiff.translate` runs exactly the same, at no extra
cost.

A translation emits up to six events, each named `<name>.translation_diff`:

| Event | Fired | Payload |
| --- | --- | --- |
| `translate` | Once per `translate` call that has something to translate, wrapping the whole thing -- including a call served entirely from cache, which never reaches the provider. A call whose source and target languages are the same, or whose values hold no translatable text at all, returns early and emits no events. | `call_id`, `from`, `to`, `provider`, `values` (number of texts), `characters` (total considered by this call) |
| `cache` | Once per such call, after checking the cache for every sentence at once -- whether or not anything is left to send the provider. | `call_id`, `provider`, `hits`, `misses` |
| `request` | Once per batch actually sent to the provider (skipped entirely on a full cache hit). | `call_id`, `provider`, `batch` (values sent), `characters` (sent by this batch) |
| `rate_limit` | Once per batch sent to the provider, only when a rate limiter is configured. | `call_id`, `provider`, `characters` |
| `usage` | Once per batch actually sent to the provider, right after `request`. | `call_id`, `provider`, `characters`, `billed_characters`, `reported`, `model` |
| `cache_error` | Only when writing the translation back to the cache fails -- after the provider has already answered. Never fires on a successful write, so it is not part of every call the way the other five are. | `call_id`, `provider`, `error` (the failed write's error class, as a string) |

**Every event above carries `call_id`.** It is generated once per
`translate` call, opaque, and never derived from the text. Before it, a
subscriber receiving `cache`, `request`, `rate_limit`, `usage` or
`cache_error` events had no way to tell which `translate` call any of them
belonged to, short of tagging `Thread.current` itself -- a workaround that
breaks the moment two translations share a thread.

**`translate`'s `characters` and `request`'s `characters` measure different
things.** `translate`'s is the total this call considered -- every
non-blank sentence, hit or miss, whether or not any of it was sent to the
provider -- so a call served entirely from cache still reports a number
instead of nothing, even though no `request` event fires for it at all.
`request`'s keeps its narrower meaning: what this one batch actually sent.
`usage`'s `characters` carries that same narrower meaning too, per batch,
like `request`'s. Same name, three events, two meanings -- a subscriber
summing the wrong one gets a wrong bill.

`cache_error` is what a failing cache write looks like from the outside:
the write itself is rescued, not the translation, which still reaches the
caller -- see
[The three write paths fail differently](caching.md#the-three-write-paths-fail-differently).
`error` is the exception's class name, never its message, which could echo
the row it failed to write. Which class you see depends on the store: a
store that redacts its own failures reports that redaction, so
`ActiveRecordCacheStore` always gives `"TranslationDiff::Error"` -- the
adapter's own class is named inside that error's (content-free) message,
not in this payload. `RedisCacheStore` does not wrap, so it gives the
driver's class, `"Redis::CannotConnectError"` and the like. Alert on the
event, not on a particular class name.

The same failure is logged at **warn**, not debug: an application whose
cache has quietly stopped accepting writes pays the provider for every
sentence, every time, and a signal only visible at debug level is one
nobody sees in production.

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
