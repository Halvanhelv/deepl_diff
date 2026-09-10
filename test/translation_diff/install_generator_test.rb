require "test_helper"
require "support/active_record_database"
require "tmpdir"

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
      GeneratedMigrationRecord.establish_connection(adapter: "sqlite3", database: ":memory:")
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
