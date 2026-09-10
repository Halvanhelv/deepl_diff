# The lazy require, the version floor and the anonymous model class, shared by the cache store and the limiter.
module TranslationDiff::ActiveRecordSupport
  MINIMUM_ACTIVE_RECORD = "7.1".freeze

  def model
    @model ||= build_model
  end

  private

  # Any ActiveRecordError, not just StatementInvalid -- ReadOnlyError carries a whole write statement too.
  def ar_error?(error)
    defined?(ActiveRecord::ActiveRecordError) && error.is_a?(ActiveRecord::ActiveRecordError)
  end

  def build_model
    require "active_record"
    ensure_supported_version!
    table = @table_name
    Class.new(@base || ::ActiveRecord::Base) { self.table_name = table }
  rescue LoadError
    raise TranslationDiff::Error,
          "#{active_record_feature} is :active_record but the `activerecord` gem is not available. " \
          'Add `gem "activerecord"` to your Gemfile.'
  end

  def ensure_supported_version!
    return if Gem::Version.new(::ActiveRecord::VERSION::STRING) >= Gem::Version.new(MINIMUM_ACTIVE_RECORD)

    raise TranslationDiff::Error,
          "the #{active_record_component} needs ActiveRecord #{MINIMUM_ACTIVE_RECORD} or newer " \
          "(found #{::ActiveRecord::VERSION::STRING}): #{active_record_upsert_detail}"
  end
end
