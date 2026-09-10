# What every rate limiter must do; a contract only one implementation runs is not a contract.
module RateLimiterContract
  def test_a_check_under_the_threshold_passes
    build_limiter(threshold: 100, interval: 60).check(50)

    assert true # reaching here means #check did not raise
  end

  def test_checks_summing_past_the_threshold_raise
    build_limiter(threshold: 100, interval: 60).check(70)
    build_limiter(threshold: 100, interval: 60).check(30)

    assert_raises(rate_limit_exceeded_error) { build_limiter(threshold: 100, interval: 60).check(1) }
  end

  def test_a_window_that_has_rolled_over_passes_again
    build_limiter(threshold: 10, interval: rollover_interval).check(10)
    assert_raises(rate_limit_exceeded_error) { build_limiter(threshold: 10, interval: rollover_interval).check(1) }

    sleep(rollover_wait)

    build_limiter(threshold: 10, interval: rollover_interval).check(1)
  end
end
