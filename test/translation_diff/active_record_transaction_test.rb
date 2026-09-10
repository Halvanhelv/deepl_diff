require "test_helper"
require "support/active_record_database"

if ActiveRecordDatabase.postgres?
  ActiveRecordDatabase.connect!

  # PostgreSQL aborts the whole transaction on a statement error; only there can poisoning actually be measured.
  class ActiveRecordCacheStoreTransactionTest < Minitest::Test
    def setup
      ActiveRecordDatabase.truncate
    end

    # The scenario the review measured: save something, translate (cache write fails), rescue, keep saving.
    def test_a_failing_write_leaves_the_callers_transaction_usable
      harness = harness_model

      harness.transaction do
        begin
          failing_store.write("a", "one")
        rescue StandardError
          nil
        end

        assert harness.create!(namespace: "harness", key_digest: "d" * 64, translation: "still usable")
      end

      assert_equal 1, harness.where(namespace: "harness").count
    end

    def test_a_successful_write_still_lands
      store = TranslationDiff::ActiveRecordCacheStore.new(namespace: "harness", ttl: 60,
                                                          table_name: "translation_diff_translations")

      harness_model.transaction { store.write("a", "one") }

      assert_equal ["one"], store.read_multi(["a"])
    end

    private

    def harness_model
      TranslationDiff::ActiveRecordCacheStore.new(namespace: "harness", ttl: 60,
                                                  table_name: "translation_diff_translations").model
    end

    # A namespace past the column's 64-character limit is a statement PostgreSQL always rejects.
    def failing_store
      TranslationDiff::ActiveRecordCacheStore.new(namespace: "x" * 100, ttl: 60,
                                                  table_name: "translation_diff_translations")
    end
  end
else
  class ActiveRecordCacheStoreTransactionTest < Minitest::Test
    def test_postgres_is_unavailable
      skip "TRANSLATION_DIFF_DATABASE_URL does not name a PostgreSQL database; " \
           "only PostgreSQL aborts a transaction on a statement error"
    end
  end
end
