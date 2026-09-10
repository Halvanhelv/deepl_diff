# Caches translations in the application's own database; ActiveRecord is required on first use, never at load.
class TranslationDiff::ActiveRecordCacheStore
  MINIMUM_ACTIVE_RECORD = "7.1".freeze

  def self.build(config)
    new(namespace: config.cache_namespace, ttl: config.cache_ttl,
        table_name: config.cache_table_name, base: config.active_record_base,
        prune_probability: config.cache_prune_probability)
  end

  def initialize(namespace:, ttl:, table_name:, base: nil, prune_probability: 0.0)
    @namespace = namespace
    @ttl = ttl
    @table_name = table_name
    @base = base
    @prune_probability = prune_probability
  end

  # One query, then the caller's order restored -- a missing or expired key is a nil in its own position.
  def read_multi(keys)
    return [] if keys.empty?

    digests = keys.map { |key| digest(key) }
    found = live.where(key_digest: digests).pluck(:key_digest, :translation).to_h
    digests.map { |d| found[d] }
  end

  def write(key, value)
    write_multi([[key, value]])
    value
  end

  # One upsert for the whole batch; the unique index makes the second write of a key replace the first.
  def write_multi(pairs)
    return pairs if pairs.empty?

    model.upsert_all(pairs.map { |key, value| row(key, value) },
                     unique_by: %i[namespace key_digest], record_timestamps: true)
    prune_sometimes
    pairs
  end

  # Reads never serve an expired row; deleting one is this, and it is the host's call when to run it.
  def prune = model.where(namespace: @namespace).where(expires_at: ...Time.now.utc).delete_all

  def model
    @model ||= build_model
  end

  private

  def row(key, value)
    { namespace: @namespace, key_digest: digest(key), translation: value, expires_at: expires_at }
  end

  def expires_at = @ttl.nil? ? nil : Time.now.utc + @ttl

  # SHA256 hex is 64 characters whatever the key was, which is what makes the unique index portable.
  def digest(key) = Digest::SHA256.hexdigest(key.to_s)

  def live
    model.where(namespace: @namespace)
         .where(expires_at: nil).or(model.where(namespace: @namespace).where(expires_at: Time.now.utc...))
  end

  def prune_sometimes
    prune if @prune_probability.positive? && rand < @prune_probability
  end

  def build_model
    require "active_record"
    ensure_supported_version!
    table = @table_name
    Class.new(@base || ::ActiveRecord::Base) { self.table_name = table }
  rescue LoadError
    raise TranslationDiff::Error,
          "the cache is :active_record but the `activerecord` gem is not available. " \
          'Add `gem "activerecord"` to your Gemfile.'
  end

  def ensure_supported_version!
    return if Gem::Version.new(::ActiveRecord::VERSION::STRING) >= Gem::Version.new(MINIMUM_ACTIVE_RECORD)

    raise TranslationDiff::Error,
          "the ActiveRecord cache store needs ActiveRecord #{MINIMUM_ACTIVE_RECORD} or newer " \
          "(found #{::ActiveRecord::VERSION::STRING}): upsert_all takes unique_by and record_timestamps there."
  end
end

TranslationDiff::Stores.register(:active_record, TranslationDiff::ActiveRecordCacheStore)
