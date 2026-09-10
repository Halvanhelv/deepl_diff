require "test_helper"
require "support/active_record_database"
require "tmpdir"
require "securerandom"

begin
  require "generators/translation_diff/install_generator"
  RAILS_GENERATORS_AVAILABLE = true
rescue LoadError
  RAILS_GENERATORS_AVAILABLE = false
end

if RAILS_GENERATORS_AVAILABLE && ActiveRecordDatabase.available?
  ActiveRecordDatabase.connect!

  # Its own connection, so applying the generated migration never touches the harness's shared one.
  class GeneratedMigrationRecord < ActiveRecord::Base
    self.abstract_class = true
  end

  class InstallGeneratorTest < Minitest::Test
    def test_the_generated_migration_matches_the_harness_schema
      Dir.mktmpdir do |dir|
        migrated = migrate_in(dir)

        %i[translation_diff_translations translation_diff_rate_limits].each do |table|
          assert_equal schema_of(::ActiveRecord::Base.connection, table), schema_of(migrated, table)
        end
      end
    end

    # A DBA hand-applying this migration (see docs/sql-cache.md) may well run it twice; it must not blow up.
    def test_the_generated_migration_can_be_applied_twice
      Dir.mktmpdir do |dir|
        connection = migrate_in(dir)

        capture_io { CreateTranslationDiffTables.new.exec_migration(connection, :up) }

        assert connection.table_exists?(:translation_diff_translations)
      end
    end

    # Only the Postgres and MySQL branches leave anything behind; SQLite's :memory: connection needs no teardown.
    def teardown
      return unless @schema

      if ActiveRecordDatabase.url.to_s.start_with?("postgres")
        ::ActiveRecord::Base.connection.execute(%(DROP SCHEMA IF EXISTS "#{@schema}" CASCADE))
      else
        ::ActiveRecord::Base.connection.execute(%(DROP DATABASE IF EXISTS `#{@schema}`))
      end
    end

    private

    def migrate_in(dir)
      generator = TranslationDiff::InstallGenerator.new([], {}, destination_root: dir)
      capture_io { generator.invoke_all }

      connection = isolated_connection
      require migration_file(dir)
      capture_io { CreateTranslationDiffTables.new.exec_migration(connection, :up) }
      connection
    end

    def isolated_connection
      url = ActiveRecordDatabase.url.to_s
      return postgres_isolated_connection if url.start_with?("postgres")
      return mysql_isolated_connection if url.match?(%r{\A(mysql2|trilogy)://})

      sqlite_isolated_connection
    end

    def sqlite_isolated_connection
      GeneratedMigrationRecord.establish_connection(adapter: "sqlite3", database: ":memory:")
      GeneratedMigrationRecord.connection
    end

    # A scratch schema on the same server, so the migration has nowhere to collide with the harness's own tables.
    def postgres_isolated_connection
      @schema = "generator_test_#{SecureRandom.hex(4)}"
      ::ActiveRecord::Base.connection.execute(%(CREATE SCHEMA "#{@schema}"))
      config = ::ActiveRecord::Base.connection_db_config.configuration_hash.merge(schema_search_path: @schema)
      GeneratedMigrationRecord.establish_connection(config)
      GeneratedMigrationRecord.connection
    end

    # MySQL has no per-connection search path, so a scratch database stands in for Postgres's scratch schema.
    def mysql_isolated_connection
      @schema = "generator_test_#{SecureRandom.hex(4)}"
      ::ActiveRecord::Base.connection.execute(%(CREATE DATABASE `#{@schema}`))
      config = ::ActiveRecord::Base.connection_db_config.configuration_hash.merge(database: @schema)
      GeneratedMigrationRecord.establish_connection(config)
      GeneratedMigrationRecord.connection
    end

    def migration_file(dir)
      Dir.glob(File.join(dir, "db/migrate/*_create_translation_diff_tables.rb")).first
    end

    def schema_of(connection, table)
      { columns: connection.columns(table).map { |c| [c.name, c.sql_type, c.null, c.default] }.sort,
        indexes: connection.indexes(table).map { |i| [i.columns.sort, i.unique] }.sort_by(&:to_s) }
    end
  end
else
  class InstallGeneratorTest < Minitest::Test
    def test_rails_generators_are_unavailable
      skip "Rails' generator classes could not be loaded; the install generator suite is skipped"
    end
  end
end
