# frozen_string_literal: true

source "https://rubygems.org"

gemspec

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
