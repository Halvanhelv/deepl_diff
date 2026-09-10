require "test_helper"
require "support/active_record_database"

if ActiveRecordDatabase.postgres?
  ActiveRecordDatabase.connect!

  # upsert_all inlines values into the SQL it sends, so PostgreSQL's own error detail can carry a whole row;
  # only a real constraint violation against a real server reproduces that, hence the PostgreSQL gate.
  class ActiveRecordCacheStoreRedactionTest < Minitest::Test
    CONSTRAINT = "no_forbidden_namespace_in_redaction_test".freeze

    def setup
      ActiveRecordDatabase.truncate
      connection.execute("ALTER TABLE translation_diff_translations ADD CONSTRAINT #{CONSTRAINT} " \
                         "CHECK (namespace <> 'forbidden-namespace')")
    end

    def teardown
      connection.execute("ALTER TABLE translation_diff_translations DROP CONSTRAINT IF EXISTS #{CONSTRAINT}")
    end

    def test_a_statement_invalid_never_carries_the_translated_content
      store = TranslationDiff::ActiveRecordCacheStore.new(namespace: "forbidden-namespace", ttl: 60,
                                                          table_name: "translation_diff_translations")

      error = assert_raises(TranslationDiff::Error) { store.write("a", "SECRET-PATIENT-NOTE-12345") }

      refute_includes error.message, "SECRET-PATIENT-NOTE-12345"
    end

    def test_the_redacted_error_names_the_adapters_own_error_class
      store = TranslationDiff::ActiveRecordCacheStore.new(namespace: "forbidden-namespace", ttl: 60,
                                                          table_name: "translation_diff_translations")

      error = assert_raises(TranslationDiff::Error) { store.write("a", "one") }

      assert_includes error.message, "PG::CheckViolation"
    end

    private

    def connection
      TranslationDiff::ActiveRecordCacheStore.new(namespace: "harness", ttl: 60,
                                                  table_name: "translation_diff_translations").model.connection
    end
  end
else
  class ActiveRecordCacheStoreRedactionTest < Minitest::Test
    def test_postgres_is_unavailable
      skip "TRANSLATION_DIFF_DATABASE_URL does not name a PostgreSQL database; " \
           "a check violation's row detail is what this test reproduces"
    end
  end
end
