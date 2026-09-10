# Throttles by counting characters into namespaced, time-bucketed rows in the application's own database.
class TranslationDiff::ActiveRecordRateLimiter
  class RateLimitExceeded < TranslationDiff::Error; end

  DEFAULT_THRESHOLD = 8000
  DEFAULT_INTERVAL = 60

  def self.build(config)
    new(namespace: config.cache_namespace, table_name: config.rate_limit_table_name,
        threshold: config.rate_limit, interval: config.rate_interval, base: config.active_record_base)
  end

  def initialize(namespace:, table_name:, threshold: DEFAULT_THRESHOLD, interval: DEFAULT_INTERVAL, base: nil)
    @namespace = namespace
    @table_name = table_name
    @threshold = threshold
    @interval = interval
    @base = base
  end

  # Approximate at a window boundary, the same way the `ratelimit` gem this replaces is.
  def check(size)
    raise RateLimitExceeded if current_total >= @threshold

    add(size)
  end

  # Buckets from before the current window; the host decides when, if ever, this runs.
  def prune = model.where(namespace: @namespace).where(bucket: ...bucket).delete_all

  def model
    @model ||= build_model
  end

  private

  def current_total = model.where(namespace: @namespace, bucket: bucket).sum(:characters)

  def bucket = Time.now.to_i / @interval

  # One statement, so two processes incrementing the same bucket cannot lose an increment between them.
  def add(size)
    size = size.to_i
    model.upsert_all([{ namespace: @namespace, bucket: bucket, characters: size }],
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
