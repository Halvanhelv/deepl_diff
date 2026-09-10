source "https://rubygems.org"

gemspec

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

# Not a runtime dependency of the gem (see the gemspec) -- lib/ only ever
# needs CGI.escape, which cgi/escape (in Ruby's default load path) still
# provides. This is here because the Google provider's test decodes the
# query string it sent, and Ruby 4.0 removed CGI.parse from the default
# load path; "install cgi gem" is Ruby's own suggested fix.
gem "cgi", "~> 0.5", require: false

# Not a runtime dependency of the gem (see the gemspec) -- the Amazon
# provider requires it lazily when it signs its first request, so an
# application using another provider never needs it installed. It is here so
# the test suite, which signs against the real library rather than a
# stand-in, has it available.
gem "aws-sigv4", "~> 1.12", require: false

# Not runtime dependencies of the gem (see the gemspec) -- ActiveRecordCacheStore
# and ActiveRecordRateLimiter require active_record lazily on first use, so an
# application caching in Redis never needs it installed. They are here so the
# suite can exercise the stores against a real database rather than a stand-in.
gem "activerecord", "~> 8.1", require: false
gem "sqlite3", "~> 2.9", require: false

# Not a runtime dependency of the gem (see the gemspec) -- only the CI job that
# sets TRANSLATION_DIFF_DATABASE_URL ever opens a Postgres connection, where
# the concurrency the SQL store and rate limiter rest on can actually be
# tested. SQLite has one writer, so most of the suite never needs this gem.
gem "pg", "~> 1.5", require: false

# Not a runtime dependency of the gem (see the gemspec) -- the generator under
# lib/generators/ is loaded only when Rails loads generators, so a non-Rails
# application never needs it installed. It is here so
# test/translation_diff/install_generator_test.rb can load it and check the
# generated migration against the schema the rest of the suite runs against,
# instead of skipping itself for want of Rails::Generators::Base.
gem "railties", "~> 8.1", require: false
