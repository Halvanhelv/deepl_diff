# Contracts

## The rate limiter contract

Like `provider`, `cache` and `segmenter`, `rate_limiter` resolves a symbol
through its own registry, `TranslationDiff::RateLimiters` -- `:redis` and
`:active_record` are registered there. `config.rate_limiter_instance` is:

- the object assigned to `config.rate_limiter`, if any -- an object still
  bypasses the registry entirely, the same way it does for `cache`;
- otherwise `nil` if both `rate_limiter` and `rate_limit` were never set --
  and `Dispatcher#throttle` checks for that `nil` and skips rate limiting
  entirely, so the common case costs nothing;
- otherwise the registered limiter named by `config.rate_limiter`, or
  `TranslationDiff::RateLimiters::Redis` when `rate_limiter` is left unset but
  `rate_limit` is set -- built from `rate_interval`, `cache_namespace`, and
  either `redis_url` (`:redis`) or `active_record_base` and
  `rate_limit_table_name` (`:active_record`; see [SQL cache](sql-cache.md)).
  `rate_limit` supplies the threshold when it is set; left unset, the
  limiter falls back to its own default -- 8,000 characters per
  `rate_interval` for both shipped limiters -- instead of crashing, so
  setting `rate_limiter` alone is enough to turn a limiter on.

An object assigned to `rate_limiter` must implement:

```ruby
# Called with the number of characters about to be sent to the provider.
# Raises when the caller-defined threshold is exceeded.
def check(size); end
```

Both shipped limiters raise `TranslationDiff::RateLimitExceeded` when the
threshold is exceeded within the interval -- one class whichever limiter is
configured, so switching from `:redis` to `:active_record` does not quietly
stop a `rescue` from matching. They raise with a
message naming the namespace, the threshold and the interval that were hit
(`"rate limit reached for translation-diff: 8000 characters per 60
seconds"`) -- never the text that tripped it. Neither `redis`
nor `connection_pool` nor `ratelimit` is a dependency of this gem:
`ratelimit` is required on the first check, so an application that
configures no `rate_limit` never needs it, and its absence raises
`TranslationDiff::Error` naming the gem to add. `activerecord` is never a
dependency either -- see [SQL cache](sql-cache.md#the-activerecord-version-floor).

**Upgrading to 3.1.0: re-validate your `rate_limit` threshold.** Before this
release, `RateLimiters::Redis` never actually limited anything -- a signature
mismatch with the `ratelimit` gem meant it recorded hits under a subject
`exceeded?` never read, so the threshold could never be reached. That bug
shipped in every release since `v1.0.2` (2023-02-16). If you have
`rate_limit` configured, your traffic has never actually been throttled by
it; upgrading makes the limiter fire for the first time, against a value you
may have set once and never seen exercised. Re-check that the threshold
still reflects the traffic you actually want to allow before you upgrade.

**`rate_interval` is silently clamped to roughly 5-600 seconds.** The
built-in limiter constructs `Ratelimit.new` with no bucket options, so the
gem's own fixed bucket span applies regardless of what you configure --
measured: `rate_interval: 3600` behaves as `600`, and `rate_interval: 1`
behaves as `5`. Combined with the fix above, an interval configured above
600 seconds is now enforced over 600 seconds instead, which trips the
limiter up to six times more eagerly than the configured value suggests.
Keep `rate_interval` within 5-600 seconds if you want the configured number
to be the enforced one.

Both the clamp above and the upgrade note before it are about
`RateLimiters::Redis`, which delegates its bucketing to the `ratelimit` gem.
`RateLimiters::ActiveRecord` owns its own bucketing instead, and its window is
sliding rather than tumbling: buckets are `rate_interval / 12` seconds wide
(floored at 1 second), and a check sums every bucket touching the trailing
`rate_interval` seconds -- including the oldest one, which is only ever
partially inside that window, summed in full rather than pro-rated. So the
window actually enforced is `rate_interval` to `rate_interval +
rate_interval / 12` seconds: slightly stricter than configured, never
looser, and with no external clamp. See
[SQL cache](sql-cache.md#the-rate-limiter).

## The segmenter contract

`config.segmenter` decides where a text node is cut into sentence-sized
cache units, the same way `config.provider` decides how a sentence gets
translated. It defaults to `:pragmatic` and can be swapped for `:simple` or
for any object implementing:

```ruby
# Returns the offsets at which a new sentence begins, always starting with 0
# and strictly increasing. Slicing the source between consecutive offsets, and
# from the last offset to the end, reconstructs the source exactly -- a wrong
# boundary never corrupts the document, it only changes how the text is
# grouped into cache units.
#
# language: is an ISO 639-1 code such as "en" or "ru" when the caller already
# knows the source language, and nil when it does not -- see below.
def split_offsets(text, language: nil); end
```

Two segmenters ship with this gem:

- **`TranslationDiff::Segmenters::Pragmatic`** (the default) wraps the
  [`pragmatic_segmenter`](https://github.com/diasks2/pragmatic_segmenter) gem,
  which ships per-language rule sets rather than one rule set applied to every
  script. Measured against the Golden Rules corpus, the de-facto benchmark for
  sentence segmentation -- the `context "Golden Rules" do` block of each of
  the 10 per-language spec files on `diasks2/pragmatic_segmenter`, 80
  exemplars in total; a sample of the same corpus is in
  `test/translation_diff/golden_rules_test.rb` -- it scores 76/80 against
  `Simple`'s 47/80, and the gap is largest on languages that have no letter
  case at all -- Arabic, Hindi, Armenian, Greek -- which `Simple` cannot
  reason about by design.

  Of the 4 exemplars `Pragmatic` misses, 3 are not boundary disagreements at
  all: `pragmatic_segmenter`'s own expected value rewrites an incidental
  newline into a space before comparing --

      "This is a sentence\ncut off in the middle because pdf."
        expected ["This is a sentence cut off in the middle because pdf."]
        ours     ["This is a sentence\ncut off in the middle because pdf."]

      "It was a cold \nnight in the city."
        expected ["It was a cold night in the city."]
        ours     ["It was a cold \nnight in the city."]

  -- and the same shape recurs once in Japanese (`"これは父の\n家です。"`, expected
  with the newline gone). In all three, `Pragmatic` finds exactly one
  sentence, agrees on where it ends, and is scored wrong only because it
  will not rewrite the source to match. Rewriting the source is exactly what
  this gem's reconstruction invariant forbids, so this is a deliberate
  choice, not a defect the score is hiding. The 1 remaining miss is a real
  boundary disagreement, in English -- see the shadowing paragraph below.

  Before segmenting, `Pragmatic` replaces every single newline (one with no
  adjoining newline) with a space in a shadow copy of the text, segments the
  shadow, and slices the *original* text at the recovered offsets --
  `pragmatic_segmenter` otherwise treats almost any single newline as a
  sentence boundary candidate even with no punctuation at all, which is a
  false split (the harmful kind) on the incidental newlines that HTML text
  nodes routinely carry from source formatting. A run of two or more
  newlines (a real paragraph break) is left alone. This costs one Golden
  Rules point (77 -> 76): one exemplar shaped like a bare list of items
  separated by single newlines, with no punctuation, now segments as one
  unit instead of three. That shape does not arise in this gem's actual
  input -- HTML list items are separated by markup into distinct text nodes
  already -- so the point is a deliberate trade, not a regression to chase.

  Language codes are normalised before reaching `pragmatic_segmenter`:
  downcased, with any region subtag after `-` or `_` dropped, and checked
  against the codes `pragmatic_segmenter` actually has rules for, falling
  back to English otherwise. DeepL -- this gem's own flagship provider --
  sends codes exactly like `"RU"` and `"EN-GB"`; without normalising,
  `pragmatic_segmenter`'s own lookup is case-sensitive and region-blind, so
  those would silently miss their rule set entirely.
- **`TranslationDiff::Segmenters::Simple`** is a zero-dependency, in-house
  segmenter. It splits conservatively on punctuation followed by whitespace,
  guarded by a handful of signals (a known abbreviation, an initial, digits on
  both sides, a URL or email, or a lowercase letter immediately following --
  the guard that gives it away as built for cased scripts). Reach for it if
  you want no extra dependency and you only ever translate from languages
  written in a cased script (Latin, Cyrillic, Greek's own script aside,
  Armenian, and similar).

Passing `from:` to `::translate` does more than skip a detection call (see
[How it works](how-it-works.md) below): it is also the only way a segmenter sees
the source language. When `from:` is omitted, the language is genuinely
unknown at the time the text is segmented -- language detection needs the
segmented text to build its sample, so segmentation cannot wait for it -- and
`Pragmatic` falls back to English rules, which can mis-segment other
languages (Russian abbreviations, for one). `Simple` ignores the argument
entirely; its rules are language-neutral.

`pragmatic_segmenter`'s cleaner rewrites the sentences it hands back in ways
shadowing does not cover -- it collapses runs of three or more spaces, and it
respaces abbreviations like `"Ph.D."` into `"Ph. D."`, among other things --
so the sentence `Pragmatic` gets back does not always appear verbatim in the
source any more. `Pragmatic` never guesses at an offset it cannot verify: it
walks the returned sentences in order, keeps every offset it locates, and
stops at the first one it cannot -- but the boundary at the end of the last
sentence it did locate is not thrown away with the rest, since it was
matched character for character too. Only the genuinely unrecoverable
remainder is coarsened into one final unit; the verified prefix before it is
still sliced off. This is a *coarsening*, not a failure -- the text still
translates correctly, the cache unit is just larger than it could have
been -- and it is silent by design,
the same way a segmenter simply not splitting a node has always been
acceptable. `TranslationDiff::Segmenters::Pragmatic::Error` (a
`TranslationDiff::Error`) still exists and is still raised, but only if
`Pragmatic` itself computes offsets that violate its own postcondition
(starting at 0, strictly increasing, all within the text) -- not by ordinary
use of `pragmatic_segmenter`, however it rewrites a sentence.
