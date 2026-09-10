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

  # Rollover is not in this contract: proving it means waiting for a bucket to turn over, and only
  # ActiveRecordRateLimiter can be made to turn one over without a real sleep. See its own test file.
end
