require "test_helper"
require "support/active_record_database"

if ActiveRecordDatabase.available?
  ActiveRecordDatabase.connect!

  class ActiveRecordSupportTest < Minitest::Test
    def test_the_cache_store_and_the_rate_limiter_share_the_same_active_record_plumbing
      assert_includes TranslationDiff::ActiveRecordCacheStore.ancestors, TranslationDiff::ActiveRecordSupport
      assert_includes TranslationDiff::ActiveRecordRateLimiter.ancestors, TranslationDiff::ActiveRecordSupport
    end

    def test_the_version_floor_is_declared_once_and_shared
      assert_same TranslationDiff::ActiveRecordSupport::MINIMUM_ACTIVE_RECORD,
                  TranslationDiff::ActiveRecordCacheStore::MINIMUM_ACTIVE_RECORD
      assert_same TranslationDiff::ActiveRecordSupport::MINIMUM_ACTIVE_RECORD,
                  TranslationDiff::ActiveRecordRateLimiter::MINIMUM_ACTIVE_RECORD
    end

    def test_each_store_instance_memoises_its_own_model_rather_than_sharing_one
      first = TranslationDiff::ActiveRecordCacheStore.new(namespace: "translation-diff", ttl: nil,
                                                          table_name: "translation_diff_translations")
      second = TranslationDiff::ActiveRecordCacheStore.new(namespace: "translation-diff", ttl: nil,
                                                           table_name: "translation_diff_translations")

      assert_same first.model, first.model
      refute_same first.model, second.model
    end
  end
end
