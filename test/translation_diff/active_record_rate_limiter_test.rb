require "test_helper"
require "support/rate_limiter_contract"
require "support/active_record_database"

if ActiveRecordDatabase.available?
  ActiveRecordDatabase.connect!

  # Moves without sleeping, so a bucket can be made to roll over on demand instead of waited out.
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

    # Advancing the clock by exactly one interval always lands in the next bucket, whatever the starting phase.
    def test_a_window_that_has_rolled_over_passes_again
      clock = MutableClock.new(Time.now)

      build_limiter(threshold: 10, interval: 60, clock: clock).check(10)
      assert_raises(rate_limit_exceeded_error) { build_limiter(threshold: 10, interval: 60, clock: clock).check(1) }

      clock.advance(60)

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

    def test_prune_deletes_buckets_older_than_the_window_and_leaves_the_current_one
      limiter = build_limiter(threshold: 1000, interval: 60)
      model.create!(namespace: "translation-diff", bucket: limiter.send(:bucket) - 1, characters: 5)

      limiter.check(10)
      deleted = limiter.prune

      assert_equal 1, deleted
      assert_equal [limiter.send(:bucket)], model.pluck(:bucket)
    end

    def test_prune_only_deletes_rows_in_its_own_namespace
      own = build_limiter(threshold: 1000, interval: 60)
      other = build_limiter(threshold: 1000, interval: 60, namespace: "other-tenant")
      model.create!(namespace: "translation-diff", bucket: own.send(:bucket) - 1, characters: 5)
      model.create!(namespace: "other-tenant", bucket: other.send(:bucket) - 1, characters: 5)

      assert_equal 1, own.prune
      assert_equal 1, model.where(namespace: "other-tenant").count
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

    private

    def rate_limit_exceeded_error = TranslationDiff::ActiveRecordRateLimiter::RateLimitExceeded

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
