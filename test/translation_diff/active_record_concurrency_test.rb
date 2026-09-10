require "test_helper"
require "support/active_record_database"

POSTGRES_DATABASE = ActiveRecordDatabase.available? && ActiveRecordDatabase.url.to_s.match?(%r{\Apostgres(ql)?://})

if POSTGRES_DATABASE
  ActiveRecordDatabase.connect!

  # SQLite has one writer, so only Postgres can put these properties under a real race.
  class ActiveRecordConcurrencyTest < Minitest::Test
    def setup
      ActiveRecordDatabase.truncate
    end

    # Two connections upserting the same unique-index row: no exception, and last write standing wins.
    def test_two_writers_racing_the_same_cache_key_do_not_raise_and_one_value_wins
      key = "concurrent-key"
      values = %w[first second]

      threads = values.map { |value| Thread.new { build_cache_store.write(key, value) } }
      threads.each(&:join)

      assert_includes values, build_cache_store.read_multi([key]).first
    end

    # Two connections upserting-and-incrementing the same bucket a hundred times each: no increment lost.
    def test_two_limiters_racing_the_same_bucket_lose_no_increment
      now = Time.now
      totals = build_rate_limiter(now).model

      threads = Array.new(2) { Thread.new { 100.times { build_rate_limiter(now).check(1) } } }
      threads.each(&:join)

      assert_equal 200, totals.sum(:characters)
    end

    private

    def build_cache_store
      TranslationDiff::ActiveRecordCacheStore.new(namespace: "translation-diff", ttl: 60,
                                                  table_name: "translation_diff_translations")
    end

    # A shared, frozen clock keeps both limiters in the same bucket for the length of the test.
    def build_rate_limiter(now)
      TranslationDiff::ActiveRecordRateLimiter.new(namespace: "translation-diff", threshold: 1_000_000,
                                                   interval: 60, table_name: "translation_diff_rate_limits",
                                                   clock: -> { now })
    end
  end
else
  class ActiveRecordConcurrencyTest < Minitest::Test
    def test_postgres_is_unavailable
      skip "TRANSLATION_DIFF_DATABASE_URL does not name a PostgreSQL database; " \
           "SQLite has one writer and cannot exercise these races"
    end
  end
end
