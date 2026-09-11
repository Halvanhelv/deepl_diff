require "test_helper"
require "support/active_record_database"

if ActiveRecordDatabase.mysql?
  ActiveRecordDatabase.connect!

  # MySQL's TEXT column tops out at 65,535 bytes; only a real MySQL server proves the migration raised that ceiling.
  class ActiveRecordStoreMysqlTextLimitTest < Minitest::Test
    class RecordingProvider < TranslationDiff::Provider
      def self.capabilities
        TranslationDiff::Capabilities.new(max_request_size: 100_000_000, max_batch_size: 1_000,
                                          max_text_size: nil, html: :none, notranslate: false,
                                          detects_language: true, reports_billing: false)
      end

      def translate(request)
        TranslationDiff::Translation::Response.build(request: request, texts: request.texts.map(&:upcase))
      end

      def detect(_text) = "en"
      def cache_key = "recording"
    end

    def setup
      ActiveRecordDatabase.truncate
      TranslationDiff.reset!
    end

    def teardown = TranslationDiff.reset!

    # The finding this migration fixes: a 75,000-byte run-on sentence used to fail the whole upsert.
    def test_a_75000_byte_sentence_caches
      store = build_store
      value = "a" * 75_000

      store.write("oversized", value)

      assert_equal [value], store.read_multi(["oversized"])
    end

    # Raising the ceiling does not remove it -- MEDIUMTEXT still caps at 16,777,215 bytes.
    def test_a_value_beyond_the_new_ceiling_still_raises_a_redacted_error
      store = build_store
      value = "a" * 16_777_216

      error = assert_raises(TranslationDiff::Error) { store.write("too-big", value) }

      assert_includes error.message, "the cache write failed"
    end

    # With fix 3 in place, that write failure degrades to "not cached", not "translation lost".
    def test_a_translator_still_returns_a_translation_the_store_cannot_hold
      store = build_store
      TranslationDiff.configure { |c| c.cache = store }
      provider = RecordingProvider.new(TranslationDiff.config)
      oversized = "a" * 16_777_216

      result = TranslationDiff::Translator.new(oversized, from: "en", to: "ru", provider: provider).call

      assert_equal oversized.upcase, result
      assert_equal 0, store.model.count
    end

    private

    def build_store
      TranslationDiff::Stores::ActiveRecord.new(namespace: "translation-diff", ttl: 60,
                                                table_name: "translation_diff_translations")
    end
  end
else
  class ActiveRecordStoreMysqlTextLimitTest < Minitest::Test
    def test_mysql_is_unavailable
      skip "TRANSLATION_DIFF_DATABASE_URL does not name a MySQL database; " \
           "only a real MySQL server enforces the TEXT column's byte ceiling"
    end
  end
end
