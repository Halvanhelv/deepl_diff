require "test_helper"
require "support/active_record_database"

if ActiveRecordDatabase.postgres?
  ActiveRecordDatabase.connect!

  # write_multi dedupes pairs.to_h before the upsert; without that, PostgreSQL raises "ON CONFLICT DO UPDATE
  # command cannot affect row a second time" the moment a batch repeats a key -- only PostgreSQL enforces this.
  class ActiveRecordWriteMultiDedupeTest < Minitest::Test
    def setup
      ActiveRecordDatabase.truncate
    end

    def test_write_multi_does_not_raise_when_a_document_repeats_the_same_sentence
      store = build_store

      store.write_multi([%w[a one], %w[a two]])

      assert_equal ["two"], store.read_multi(["a"])
    end

    # Proves the dedupe in write_multi is load-bearing, by running the same batch through the undeduped shape
    # write_multi builds internally -- without pairs.to_h, this exact scenario raises on PostgreSQL.
    def test_without_the_dedupe_postgresql_raises_on_a_repeated_key_in_one_batch
      store = build_store
      pairs = [%w[a one], %w[a two]]

      error = assert_raises(ActiveRecord::StatementInvalid) do
        store.model.transaction(requires_new: true) do
          rows = pairs.map { |key, value| store.send(:row, key, value) }
          store.model.upsert_all(rows, unique_by: %i[namespace key_digest], record_timestamps: true)
        end
      end

      assert_match(/cannot affect row a second time/, error.message)
    end

    private

    def build_store
      TranslationDiff::Stores::ActiveRecord.new(namespace: "translation-diff", ttl: 60,
                                                table_name: "translation_diff_translations")
    end
  end
else
  class ActiveRecordWriteMultiDedupeTest < Minitest::Test
    def test_postgres_is_unavailable
      skip "TRANSLATION_DIFF_DATABASE_URL does not name a PostgreSQL database; " \
           "only PostgreSQL raises when an upsert batch repeats a conflict key"
    end
  end
end
