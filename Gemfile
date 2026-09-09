# frozen_string_literal: true

source "https://rubygems.org"

gemspec

# json 3.0 dropped the positional `opts` argument that Faraday::Response::Json
# still passes to JSON.parse, which turns every JSON response Faraday parses
# into a Faraday::ParsingError. Pinned here, not in the gemspec, because it is
# a transitive dependency of faraday rather than one of ours.
gem "json", "< 3", require: false

# Not a runtime dependency of the gem (see the gemspec) -- the DeepL
# provider requires it lazily at build time. It is only here so the test
# suite, which exercises that provider against the real deepl-rb objects,
# has it available.
gem "deepl-rb", "~> 3.9", require: false

# Not runtime dependencies of the gem (see the gemspec) -- Configuration#
# redis_pool requires them lazily, and RedisCacheStore/RedisRateLimiter
# duck-type against whatever a caller's connection pool yields. They are
# only here so the test suite, which builds real pools against these
# classes, has them available.
gem "connection_pool", "~> 2.4", require: false
gem "redis", "~> 5.0", require: false
gem "redis-namespace", "~> 1.11", require: false

# Not a runtime dependency of the gem (see the gemspec) -- RedisRateLimiter
# requires it lazily on the first check, so an application that configures no
# rate limit never needs it installed. It is only here so the test suite,
# which exercises the limiter against the real Ratelimit class rather than a
# stand-in, has it available.
gem "ratelimit", "~> 1.1", require: false

# Not a runtime dependency of the gem (see the gemspec) -- the Google
# provider requires it lazily at build time, so an application using DeepL
# never needs it installed. It is only here so the test suite, which
# exercises that provider's build path against the real
# Google::Cloud::Translate::V2 objects, has it available.
gem "google-cloud-translate-v2", "~> 1.2", require: false
