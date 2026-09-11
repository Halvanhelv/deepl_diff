# Throttles by counting characters into namespaced, time-bucketed rows in the application's own database.
class TranslationDiff::RateLimiters::ActiveRecord
  include TranslationDiff::ActiveRecord::Support

  class RateLimitExceeded < TranslationDiff::Error; end

  DEFAULT_THRESHOLD = 8000
  DEFAULT_INTERVAL = 60

  # A bucket a twelfth of the interval wide caps a window's slop at under 10%, the same shape the `ratelimit` gem
  # gets from its own fixed five-second buckets at the default 60-second interval.
  BUCKET_FRACTION = 12

  # An unset rate_limit must mean DEFAULT_THRESHOLD, not the nil that would override that keyword default.
  def self.build(config)
    options = { namespace: config.cache_namespace, table_name: config.rate_limit_table_name,
                interval: config.rate_interval, base: config.active_record_base }
    options[:threshold] = config.rate_limit unless config.rate_limit.nil?
    new(**options)
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
    raise RateLimitExceeded, exceeded_message if current_total >= @threshold

    add(size)
  rescue StandardError => e
    raise unless ar_error?(e)

    raise redacted_error(e), cause: nil
  end

  # The limiter's own statements carry counts, not content -- but a ReadOnlyError quotes the statement, and
  # a raw ActiveRecord error from inside a translate call tells a caller nothing about which gem it came from.
  def redacted_error(error)
    adapter_error = error.cause&.class || error.class
    TranslationDiff::Error.new("the rate limit check failed (#{adapter_error}): a read or upsert on " \
                               "#{@table_name}(namespace, bucket, characters)")
  end

  # Counts and settings, never a character of what was being translated.
  def exceeded_message
    "rate limit reached for #{@namespace}: #{@threshold} characters per #{@interval} seconds"
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
    table = connection.quote_table_name(model.table_name)
    options = { on_duplicate: Arel.sql("characters = #{table}.characters + #{size}") }
    options[:unique_by] = %i[namespace bucket] if connection.supports_insert_conflict_target?
    options
  end

  def active_record_feature = "the rate limiter"
  def active_record_component = "ActiveRecord rate limiter"
  def active_record_upsert_detail = "upsert_all takes unique_by there."
end

TranslationDiff::RateLimiters.register(:active_record, TranslationDiff::RateLimiters::ActiveRecord)
