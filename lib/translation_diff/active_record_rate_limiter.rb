# Throttles by counting characters into namespaced, time-bucketed rows in the application's own database.
class TranslationDiff::ActiveRecordRateLimiter
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

  # Buckets that have fully aged out of the window as of now; the host decides when, if ever, this runs.
  def prune = model.where(namespace: @namespace).where(bucket: ...(oldest_bucket + 1)).delete_all

  def model
    @model ||= build_model
  end

  private

  def current_total
    model.where(namespace: @namespace, bucket: (oldest_bucket + 1)..current_bucket).sum(:characters)
  end

  def current_bucket = now / @bucket_width

  def oldest_bucket = (now - @interval) / @bucket_width

  def now = @clock.call.to_i

  # One statement, so two processes incrementing the same bucket cannot lose an increment between them.
  # A negative size would otherwise hand back headroom it never used, so it is clamped before it reaches SQL.
  def add(size)
    size = size.to_i.clamp(0..)
    model.upsert_all([{ namespace: @namespace, bucket: current_bucket, characters: size }],
                     unique_by: %i[namespace bucket],
                     on_duplicate: Arel.sql("characters = #{model.table_name}.characters + #{size}"))
  end

  def build_model
    require "active_record"
    ensure_supported_version!
    table = @table_name
    Class.new(@base || ::ActiveRecord::Base) { self.table_name = table }
  rescue LoadError
    raise TranslationDiff::Error,
          "the rate limiter is :active_record but the `activerecord` gem is not available. " \
          'Add `gem "activerecord"` to your Gemfile.'
  end

  def ensure_supported_version!
    minimum = TranslationDiff::ActiveRecordCacheStore::MINIMUM_ACTIVE_RECORD
    return if Gem::Version.new(::ActiveRecord::VERSION::STRING) >= Gem::Version.new(minimum)

    raise TranslationDiff::Error,
          "the ActiveRecord rate limiter needs ActiveRecord #{minimum} or newer " \
          "(found #{::ActiveRecord::VERSION::STRING}): upsert_all takes unique_by there."
  end
end

TranslationDiff::RateLimiters.register(:active_record, TranslationDiff::ActiveRecordRateLimiter)
