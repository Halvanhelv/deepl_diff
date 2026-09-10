require "test_helper"
require "support/rate_limiter_contract"
require "support/active_record_database"

if ActiveRecordDatabase.available?
  ActiveRecordDatabase.connect!

  # Moves without sleeping, so a bucket can be made to roll over on demand -- and holds still, so a real
  # boundary cannot fall between two reads of it, which is what made the prune tests flake.
  class MutableClock
    def initialize(now) = @now = now
    def call = @now
    def advance(seconds) = @now += seconds
  end

  class ActiveRecordRateLimiterTest < Minitest::Test
    include RateLimiterContract

    def setup
      ActiveRecordDatabase.truncate
    end

    # The window covers interval..interval + bucket_width seconds, erring strict: the oldest bucket is only ever
    # partially inside it, so a full interval alone does not guarantee it has rolled past -- one more bucket does.
    def test_a_window_that_has_rolled_over_passes_again
      clock = MutableClock.new(Time.now)

      build_limiter(threshold: 10, interval: 60, clock: clock).check(10)
      assert_raises(rate_limit_exceeded_error) { build_limiter(threshold: 10, interval: 60, clock: clock).check(1) }

      clock.advance(65)

      build_limiter(threshold: 10, interval: 60, clock: clock).check(1)
    end

    def model
      TranslationDiff::ActiveRecordRateLimiter.new(namespace: "translation-diff",
                                                   table_name: "translation_diff_rate_limits").model
    end

    def test_two_limiters_sharing_a_namespace_see_each_others_characters
      first = build_limiter(threshold: 100, interval: 60)
      second = build_limiter(threshold: 100, interval: 60)

      first.check(60)
      second.check(40)

      assert_raises(rate_limit_exceeded_error) { first.check(1) }
    end

    def test_two_namespaces_do_not_see_each_other
      tenant_a = build_limiter(threshold: 100, interval: 60, namespace: "tenant-a")
      tenant_b = build_limiter(threshold: 100, interval: 60, namespace: "tenant-b")

      tenant_a.check(90)
      tenant_b.check(90) # would raise if the namespaces were not isolated

      assert true
    end

    # int4 overflows at 2**31; any rate_interval under 24 makes the bucket the epoch second, which crosses that
    # boundary in January 2038 -- bucket is bigint precisely so a real epoch-second value like this one fits.
    def test_a_bucket_beyond_int32_range_is_stored_and_read_back
      far_future_bucket = (2**31) + 1

      model.create!(namespace: "translation-diff", bucket: far_future_bucket, characters: 5)

      assert_equal far_future_bucket, model.find_by(namespace: "translation-diff").bucket
    end

    # Rails' DatabaseSelector sets this on every GET, and the ReadOnlyError it raises quotes the statement.
    def test_a_write_refused_by_rails_is_reported_as_this_gem_s_own_error
      limiter = build_limiter(threshold: 1000, interval: 60)

      error = assert_raises(TranslationDiff::Error) do
        ::ActiveRecord::Base.while_preventing_writes { limiter.check(10) }
      end

      refute_instance_of ::ActiveRecord::ReadOnlyError, error
      assert_match(/the rate limit check failed/, error.message)
      assert_nil error.cause
    end

    def test_prune_deletes_buckets_older_than_the_window_and_leaves_the_current_one
      limiter = build_limiter(threshold: 1000, interval: 60, clock: frozen_clock)
      model.create!(namespace: "translation-diff", bucket: limiter.send(:oldest_bucket) - 1, characters: 5)

      limiter.check(10)
      deleted = limiter.prune

      assert_equal 1, deleted
      assert_equal [limiter.send(:current_bucket)], model.pluck(:bucket)
    end

    # The oldest bucket is only ever partially inside the window (see current_total), so prune leaving it alone
    # is what keeps pruning from quietly undoing the strictness that sum starting at oldest_bucket relies on.
    def test_prune_leaves_the_oldest_bucket_because_the_window_still_counts_it
      limiter = build_limiter(threshold: 1000, interval: 60, clock: frozen_clock)
      model.create!(namespace: "translation-diff", bucket: limiter.send(:oldest_bucket), characters: 5)

      deleted = limiter.prune

      assert_equal 0, deleted
      assert_equal [limiter.send(:oldest_bucket)], model.pluck(:bucket)
    end

    def test_prune_only_deletes_rows_in_its_own_namespace
      own = build_limiter(threshold: 1000, interval: 60, clock: frozen_clock)
      model.create!(namespace: "translation-diff", bucket: own.send(:oldest_bucket) - 1, characters: 5)
      model.create!(namespace: "other-tenant", bucket: own.send(:oldest_bucket) - 1, characters: 5)

      assert_equal 1, own.prune
      assert_equal 1, model.where(namespace: "other-tenant").count
    end

    # The bug this review caught: a tumbling counter let a nominal 8000/60s throttle through twice, back to back.
    def test_a_check_at_the_end_of_one_window_still_counts_two_seconds_into_the_next
      clock = MutableClock.new(Time.at(59))
      limiter = build_limiter(threshold: 8000, interval: 60, clock: clock)

      limiter.check(8000)
      clock.advance(2)

      assert_raises(rate_limit_exceeded_error) { limiter.check(8000) }
    end

    # The dropped partial oldest bucket: 56 real seconds have passed, well inside a true 60-second window, but
    # a tumbling (oldest_bucket + 1) start point had already stopped counting the first deposit's bucket.
    def test_a_deposit_inside_the_window_still_blocks_a_later_check
      clock = MutableClock.new(Time.at(4))
      limiter = build_limiter(threshold: 8000, interval: 60, clock: clock)

      limiter.check(8000)
      clock.advance(56)

      assert_raises(rate_limit_exceeded_error) { limiter.check(1) }
    end

    def test_a_negative_size_does_not_hand_back_headroom
      limiter = build_limiter(threshold: 1000, interval: 60)
      limiter.check(500)

      limiter.check(-1000)

      assert_equal 500, model.sum(:characters)
    end

    # `size` is interpolated into the on_duplicate SQL fragment, so a value with no clean integer must not reach it.
    def test_a_non_integer_size_only_contributes_its_leading_digits
      limiter = build_limiter(threshold: 1_000, interval: 60)

      limiter.check("5); DROP TABLE translation_diff_rate_limits; --")

      assert_equal 5, model.sum(:characters)
      assert_equal [5], model.pluck(:characters)
    end

    def test_build_takes_its_settings_from_the_configuration
      config = TranslationDiff::Configuration.new
      config.cache_namespace = "from-config"
      config.rate_limit_table_name = "translation_diff_rate_limits"
      config.rate_limit = 100
      config.rate_interval = 60

      built = TranslationDiff::ActiveRecordRateLimiter.build(config)
      built.check(1)

      assert_equal ["from-config"], built.model.pluck(:namespace)
    end

    # Setting only `rate_limiter`, the config option that turns this limiter on, must not crash every call.
    def test_build_falls_back_to_the_default_threshold_when_rate_limit_is_unset
      config = TranslationDiff::Configuration.new
      config.rate_limiter = :active_record

      built = TranslationDiff::ActiveRecordRateLimiter.build(config)

      assert_equal TranslationDiff::ActiveRecordRateLimiter::DEFAULT_THRESHOLD, built.instance_variable_get(:@threshold)
      built.check(1)
    end

    def test_add_omits_unique_by_when_the_connection_does_not_support_a_conflict_target
      limiter = build_limiter(threshold: 100, interval: 60)
      connection = Class.new do
        def supports_insert_conflict_target? = false
        def quote_table_name(name) = %("#{name}")
      end.new

      options = limiter.send(:upsert_options, connection, 1)

      refute_includes options.keys, :unique_by
    end

    def test_add_keeps_unique_by_when_the_connection_supports_a_conflict_target
      limiter = build_limiter(threshold: 100, interval: 60)
      connection = Class.new do
        def supports_insert_conflict_target? = true
        def quote_table_name(name) = %("#{name}")
      end.new

      options = limiter.send(:upsert_options, connection, 1)

      assert_includes options.keys, :unique_by
    end

    def test_add_quotes_the_table_name_in_the_on_duplicate_fragment
      limiter = build_limiter(threshold: 100, interval: 60)
      connection = limiter.model.connection

      options = limiter.send(:upsert_options, connection, 1)

      assert_includes options[:on_duplicate].to_s, connection.quote_table_name(limiter.model.table_name)
    end

    private

    def rate_limit_exceeded_error = TranslationDiff::ActiveRecordRateLimiter::RateLimitExceeded

    # Held still, so a five-second bucket boundary cannot fall between two reads of the clock.
    def frozen_clock = MutableClock.new(Time.at(1_700_000_000))

    def build_limiter(threshold:, interval:, namespace: "translation-diff", clock: -> { Time.now })
      TranslationDiff::ActiveRecordRateLimiter.new(namespace: namespace, threshold: threshold, interval: interval,
                                                   table_name: "translation_diff_rate_limits", clock: clock)
    end
  end
else
  class ActiveRecordRateLimiterTest < Minitest::Test
    def test_active_record_is_unavailable
      skip "active_record could not be loaded on this Ruby; the SQL rate limiter suite is skipped"
    end
  end
end
