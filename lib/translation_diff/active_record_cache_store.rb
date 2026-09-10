# Caches translations in the application's own database; ActiveRecord is required on first use, never at load.
class TranslationDiff::ActiveRecordCacheStore
  include TranslationDiff::ActiveRecordSupport

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

    # A savepoint, not the caller's own transaction: a failed write must not abort a transaction it does not own.
    model.transaction(requires_new: true) do
      model.upsert_all(pairs.to_h.map { |key, value| row(key, value) }, **upsert_options(model.connection))
    end
    prune_sometimes
    pairs
  rescue StandardError => e
    raise unless ar_error?(e)

    raise redacted_error(e), cause: nil
  end

  # Reads never serve an expired row; deleting one is this, and it is the host's call when to run it.
  def prune = model.where(namespace: @namespace).where(expires_at: ...Time.now.utc).delete_all

  private

  # MySQL's adapter never answers true here and its ON DUPLICATE KEY UPDATE already targets every unique key.
  def upsert_options(connection)
    options = { record_timestamps: true }
    options[:unique_by] = %i[namespace key_digest] if connection.supports_insert_conflict_target?
    options
  end

  # upsert_all inlines values into the statement it sends, so the adapter's own message can carry a whole row --
  # this names the adapter's error class and the statement's shape, never the row a caller's logger already has.
  def redacted_error(error)
    adapter_error = error.cause&.class || error.class
    TranslationDiff::Error.new("the cache write failed (#{adapter_error}): an upsert into " \
                               "#{@table_name}(namespace, key_digest, translation, expires_at)")
  end

  # Its own message, naming the statement prune actually runs -- a failed prune is not a failed upsert.
  def redacted_prune_error(error)
    adapter_error = error.cause&.class || error.class
    TranslationDiff::Error.new("the cache prune failed (#{adapter_error}): a delete from " \
                               "#{@table_name}(namespace, expires_at)")
  end

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

  # Its own savepoint, not write's -- a failing prune must not poison a transaction the caller owns either.
  def prune_sometimes
    return unless @prune_probability.positive? && rand < @prune_probability

    model.transaction(requires_new: true) { prune }
  rescue StandardError => e
    raise unless ar_error?(e)

    raise redacted_prune_error(e), cause: nil
  end

  def active_record_feature = "the cache"
  def active_record_component = "ActiveRecord cache store"
  def active_record_upsert_detail = "upsert_all takes unique_by and record_timestamps there."
end

TranslationDiff::Stores.register(:active_record, TranslationDiff::ActiveRecordCacheStore)
