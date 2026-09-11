require "test_helper"
require "support/active_record_database"

if ActiveRecordDatabase.postgres?
  ActiveRecordDatabase.connect!

  # PostgreSQL aborts the whole transaction on a statement error; only there can poisoning actually be measured.
  class ActiveRecordStoreTransactionTest < Minitest::Test
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
      store = TranslationDiff::Stores::ActiveRecord.new(namespace: "harness", ttl: 60,
                                                        table_name: "translation_diff_translations")

      harness_model.transaction { store.write("a", "one") }

      assert_equal ["one"], store.read_multi(["a"])
    end

    # The path the review found reachable again: prune runs after write's own savepoint has already closed.
    def test_a_failing_prune_leaves_the_callers_transaction_usable
      store = store_with_a_pending_prune
      harness = harness_model

      harness.transaction do
        write_ignoring_errors(store, "fresh", "two")

        assert harness.create!(namespace: "harness", key_digest: "d" * 64, translation: "still usable")
      end

      assert_equal 1, harness.where(namespace: "harness").count
    ensure
      remove_failing_delete_trigger
    end

    # The write itself still lands even though the prune that follows it fails, since each has its own savepoint.
    def test_a_failing_prune_does_not_undo_the_write_that_triggered_it
      store = store_with_a_pending_prune

      write_ignoring_errors(store, "fresh", "two")

      assert_equal ["two"], store.read_multi(["fresh"])
    ensure
      remove_failing_delete_trigger
    end

    # The regression the review found: a failing prune was reported as the wrong statement, an upsert.
    def test_a_failing_prunes_error_describes_the_delete_not_the_upsert
      store = store_with_a_pending_prune

      error = assert_raises(TranslationDiff::Error) { store.write("fresh", "two") }

      refute_includes error.message, "upsert"
      assert_includes error.message, "prune"
    ensure
      remove_failing_delete_trigger
    end

    private

    # An expired row plus a trigger that always fails its DELETE, so the write that follows always triggers a prune.
    def store_with_a_pending_prune
      store = pruning_store
      store.write("expired", "one")
      expire(store, "expired")
      install_failing_delete_trigger
      store
    end

    def pruning_store
      TranslationDiff::Stores::ActiveRecord.new(namespace: "translation-diff", ttl: 60,
                                                table_name: "translation_diff_translations",
                                                prune_probability: 1.0)
    end

    def expire(store, key)
      digest = Digest::SHA256.hexdigest(key)
      store.model.where(key_digest: digest).update_all(expires_at: Time.now.utc - 1)
    end

    def write_ignoring_errors(store, key, value)
      store.write(key, value)
    rescue StandardError
      nil
    end

    # A trigger, not a constraint: only a per-row trigger can make the DELETE itself fail, not an INSERT.
    def install_failing_delete_trigger
      harness_model.connection.execute(<<~SQL)
        CREATE OR REPLACE FUNCTION translation_diff_transaction_test_fail_delete() RETURNS trigger AS $$
        BEGIN RAISE EXCEPTION 'simulated prune failure'; END; $$ LANGUAGE plpgsql;
        CREATE TRIGGER translation_diff_transaction_test_fail_delete BEFORE DELETE
        ON translation_diff_translations FOR EACH ROW
        EXECUTE FUNCTION translation_diff_transaction_test_fail_delete();
      SQL
    end

    def remove_failing_delete_trigger
      connection = harness_model.connection
      connection.execute("DROP TRIGGER IF EXISTS translation_diff_transaction_test_fail_delete " \
                         "ON translation_diff_translations")
      connection.execute("DROP FUNCTION IF EXISTS translation_diff_transaction_test_fail_delete()")
    end

    def harness_model
      TranslationDiff::Stores::ActiveRecord.new(namespace: "harness", ttl: 60,
                                                table_name: "translation_diff_translations").model
    end

    # A namespace past the column's 64-character limit is a statement PostgreSQL always rejects.
    def failing_store
      TranslationDiff::Stores::ActiveRecord.new(namespace: "x" * 100, ttl: 60,
                                                table_name: "translation_diff_translations")
    end
  end
else
  class ActiveRecordStoreTransactionTest < Minitest::Test
    def test_postgres_is_unavailable
      skip "TRANSLATION_DIFF_DATABASE_URL does not name a PostgreSQL database; " \
           "only PostgreSQL aborts a transaction on a statement error"
    end
  end
end
