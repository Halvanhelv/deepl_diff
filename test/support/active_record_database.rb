# SQLite by default so the suite needs no service; TRANSLATION_DIFF_DATABASE_URL points it at Postgres in CI.
module ActiveRecordDatabase
  def self.available?
    return @available if defined?(@available)

    @available = begin
      require "active_record"
      true
    rescue LoadError
      false
    end
  end

  def self.connect!
    ::ActiveRecord::Base.establish_connection(url || { adapter: "sqlite3", database: ":memory:" })
    define_schema
  end

  def self.url = ENV.fetch("TRANSLATION_DIFF_DATABASE_URL", nil)

  # Both tables so Task 3's migration has something to be checked against; only the first is used so far.
  def self.define_schema
    connection = ::ActiveRecord::Base.connection
    return if connection.table_exists?(:translation_diff_translations)

    define_translations_table(connection)
    define_rate_limits_table(connection)
  end

  def self.define_translations_table(connection)
    connection.create_table :translation_diff_translations do |t|
      t.string :namespace, null: false, limit: 64
      t.string :key_digest, null: false, limit: 64
      t.text :translation, null: false
      t.datetime :expires_at
      t.timestamps
    end
    connection.add_index :translation_diff_translations, %i[namespace key_digest],
                         unique: true, name: "index_translation_diff_translations_on_key"
    connection.add_index :translation_diff_translations, :expires_at
  end

  def self.define_rate_limits_table(connection)
    connection.create_table :translation_diff_rate_limits do |t|
      t.string :namespace, null: false, limit: 64
      t.integer :bucket, null: false
      t.integer :characters, null: false, default: 0
    end
    connection.add_index :translation_diff_rate_limits, %i[namespace bucket],
                         unique: true, name: "index_translation_diff_rate_limits_on_bucket"
  end

  # Wipes both tables between tests; a fresh in-memory SQLite has nothing else to reset.
  def self.truncate
    ::ActiveRecord::Base.connection.execute("DELETE FROM translation_diff_translations")
    ::ActiveRecord::Base.connection.execute("DELETE FROM translation_diff_rate_limits")
  end
end
