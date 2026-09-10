# Rate limiters, by name; assigning an object to `config.rate_limiter` bypasses this entirely.
TranslationDiff::RateLimiters = TranslationDiff::Registry.new("rate limiter")
