require "test_helper"
require "support/active_record_database"

if ActiveRecordDatabase.postgres?
  ActiveRecordDatabase.connect!

  # The gap task 3 found: a real failing prune, reached through the translator, used to lose a translation
  # already paid for at the provider -- only a real trigger-forced prune failure against PostgreSQL proves it.
  class TranslatorCacheFailureTest < Minitest::Test
    class RecordingProvider < TranslationDiff::Provider
      def self.capabilities
        TranslationDiff::Capabilities.new(max_request_size: 1_000, max_batch_size: 10, max_text_size: nil,
                                          html: :none, notranslate: false, detects_language: true,
                                          reports_billing: false)
      end

      def translate(request)
        TranslationDiff::Translation::Response.build(request: request, texts: request.texts.map(&:upcase))
      end

      def detect(_text) = "en"
      def cache_key = "recording"
    end

    class Recorder
      attr_reader :events

      def initialize = @events = []

      def instrument(name, payload)
        @events << [name, payload]
        yield if block_given?
      end
    end

    def setup
      ActiveRecordDatabase.truncate
      TranslationDiff.reset!
    end

    def teardown
      TranslationDiff.reset!
      remove_failing_delete_trigger
    end

    def test_a_failing_prune_still_returns_the_translation_already_paid_for
      recorder = Recorder.new
      TranslationDiff.configure do |c|
        c.cache = store_with_a_pending_prune
        c.instrumenter = recorder
      end
      provider = RecordingProvider.new(TranslationDiff.config)

      result = TranslationDiff::Translator.new("brand new sentence.", from: "en", to: "ru", provider: provider).call

      assert_equal "BRAND NEW SENTENCE.", result
      assert_includes recorder.events.map(&:first), "cache_error.translation_diff"
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
      TranslationDiff::ActiveRecordCacheStore.new(namespace: "translation-diff", ttl: 60,
                                                  table_name: "translation_diff_translations",
                                                  prune_probability: 1.0)
    end

    def expire(store, key)
      digest = Digest::SHA256.hexdigest(key)
      store.model.where(key_digest: digest).update_all(expires_at: Time.now.utc - 1)
    end

    def install_failing_delete_trigger
      harness_model.connection.execute(<<~SQL)
        CREATE OR REPLACE FUNCTION translator_cache_failure_test_fail_delete() RETURNS trigger AS $$
        BEGIN RAISE EXCEPTION 'simulated prune failure'; END; $$ LANGUAGE plpgsql;
        CREATE TRIGGER translator_cache_failure_test_fail_delete BEFORE DELETE
        ON translation_diff_translations FOR EACH ROW
        EXECUTE FUNCTION translator_cache_failure_test_fail_delete();
      SQL
    end

    def remove_failing_delete_trigger
      connection = harness_model.connection
      connection.execute("DROP TRIGGER IF EXISTS translator_cache_failure_test_fail_delete " \
                         "ON translation_diff_translations")
      connection.execute("DROP FUNCTION IF EXISTS translator_cache_failure_test_fail_delete()")
    end

    def harness_model
      TranslationDiff::ActiveRecordCacheStore.new(namespace: "harness", ttl: 60,
                                                  table_name: "translation_diff_translations").model
    end
  end
else
  class TranslatorCacheFailureTest < Minitest::Test
    def test_postgres_is_unavailable
      skip "TRANSLATION_DIFF_DATABASE_URL does not name a PostgreSQL database; " \
           "only PostgreSQL aborts a transaction on a statement error"
    end
  end
end
