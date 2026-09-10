# Throttles by counting characters into namespaced, time-bucketed rows in the application's own database.
class TranslationDiff::ActiveRecordRateLimiter
  include TranslationDiff::ActiveRecordSupport

  class RateLimitExceeded < TranslationDiff::Error; end

  DEFAULT_THRESHOLD = 8000
  DEFAULT_INTERVAL = 60

  # A bucket a twelfth of the interval wide caps a window's slop at under 10%, the same shape the `ratelimit` gem
  # gets from its own fixed five-second buckets at the default 60-second interval.
  BUCKET_FRACTION = 12

  def self.build(config)
    new(namespace: config.cache_namespace, table_name: config.rate_limit_table_name,
        threshold: config.rate_limit, interval: config.rate_interval, base: config.active_record_base)
  end

  def initialize(namespace:, table_name:, threshold: DEFAULT_THRESHOLD, interval: DEFAULT_INTERVAL, base: nil,
                 clock: -> { Time.now })
    @namespace = namespace
    @table_name = table_name
    @threshold = threshold
    @interval = interval
    @base = base
    @clock = clock
    @bucket_width = [@interval / BUCKET_FRACTION, 1].max
  end

  # A sliding window: every bucket covering the last `interval` seconds is summed, not just the current one.
  def check(size)
    raise RateLimitExceeded if current_total >= @threshold

    add(size)
  end

  # Buckets that have fully aged out of the window as of now; the oldest bucket itself is still counted by it.
  def prune = model.where(namespace: @namespace).where(bucket: ...oldest_bucket).delete_all

  private

  # The oldest bucket is only ever partially inside the window, so summing from it, not past it, errs strict.
  def current_total
    model.where(namespace: @namespace, bucket: oldest_bucket..current_bucket).sum(:characters)
  end

  def current_bucket = now / @bucket_width

  def oldest_bucket = (now - @interval) / @bucket_width

  def now = @clock.call.to_i

  # One statement, so two processes incrementing the same bucket cannot lose an increment between them.
  # A negative size would otherwise hand back headroom it never used, so it is clamped before it reaches SQL.
  def add(size)
    size = size.to_i.clamp(0..)
    model.upsert_all([{ namespace: @namespace, bucket: current_bucket, characters: size }],
                     **upsert_options(model.connection, size))
  end

  # MySQL's adapter never answers true here and its ON DUPLICATE KEY UPDATE already targets every unique key.
  def upsert_options(connection, size)
    options = { on_duplicate: Arel.sql("characters = #{model.table_name}.characters + #{size}") }
    options[:unique_by] = %i[namespace bucket] if connection.supports_insert_conflict_target?
    options
  end

  def active_record_feature = "the rate limiter"
  def active_record_component = "ActiveRecord rate limiter"
  def active_record_upsert_detail = "upsert_all takes unique_by there."
end

TranslationDiff::RateLimiters.register(:active_record, TranslationDiff::ActiveRecordRateLimiter)
