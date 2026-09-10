require "test_helper"
require "support/cache_store_contract"
require "support/batching_cache_store_contract"
require "support/active_record_database"

if ActiveRecordDatabase.available?
  ActiveRecordDatabase.connect!

  class ActiveRecordCacheStoreTest < Minitest::Test
    include CacheStoreContract
    include BatchingCacheStoreContract

    attr_reader :store

    def setup
      ActiveRecordDatabase.truncate
      @store = build_store
    end

    def model = store.model

    def digest_of(key) = Digest::SHA256.hexdigest(key)

    def test_an_expired_row_is_not_read
      store.write("a", "one")
      model.update_all(expires_at: Time.now.utc - 1)

      assert_equal [nil], store.read_multi(["a"])
    end

    def test_two_namespaces_do_not_see_each_other
      store.write("a", "one")
      other = build_store(namespace: "other-tenant")

      assert_equal [nil], other.read_multi(["a"])
    end

    def test_the_cache_key_itself_is_never_stored
      store.write("deepl:en:ru:abc", "one")

      refute_includes model.first.attributes.values.join, "deepl:en:ru:abc"
    end

    def test_prune_deletes_expired_rows_and_leaves_live_ones
      store.write("live", "one")
      store.write("dead", "two")
      model.where(key_digest: digest_of("dead")).update_all(expires_at: Time.now.utc - 1)

      assert_equal 1, store.prune
      assert_equal ["one"], store.read_multi(["live"])
    end

    def test_a_nil_cache_ttl_writes_a_row_that_never_expires
      config = TranslationDiff::Configuration.new
      config.cache_namespace = "translation-diff"
      config.cache_table_name = "translation_diff_translations"
      config.cache_ttl = nil

      TranslationDiff::ActiveRecordCacheStore.build(config).write("a", "one")

      assert_nil model.first.expires_at
    end

    def test_a_zero_cache_ttl_writes_a_row_that_never_expires_instead_of_already_expired
      config = TranslationDiff::Configuration.new
      config.cache_namespace = "translation-diff"
      config.cache_table_name = "translation_diff_translations"
      config.cache_ttl = 0

      TranslationDiff::ActiveRecordCacheStore.build(config).write("a", "one")

      assert_nil model.first.expires_at
    end

    def test_prune_only_deletes_rows_in_its_own_namespace
      other = build_store(namespace: "other-tenant")
      expire(store, "a")
      expire(other, "b")

      assert_equal 1, store.prune
      assert_equal 1, model.count
    end

    def test_write_multi_with_the_same_key_twice_in_one_batch_stores_the_last_value
      store.write_multi([%w[a one], %w[a two]])

      assert_equal ["two"], store.read_multi(["a"])
    end

    def test_write_after_write_multi_still_replaces_the_key
      store.write_multi([%w[a one], %w[a two]])
      store.write("a", "three")

      assert_equal ["three"], store.read_multi(["a"])
    end

    def test_build_takes_its_settings_from_the_configuration
      config = TranslationDiff::Configuration.new
      config.cache_namespace = "from-config"
      config.cache_table_name = "translation_diff_translations"

      built = TranslationDiff::ActiveRecordCacheStore.build(config)
      built.write("a", "one")

      assert_equal "from-config", built.model.first.namespace
    end

    def test_write_multi_omits_unique_by_when_the_connection_does_not_support_a_conflict_target
      connection = Class.new { def supports_insert_conflict_target? = false }.new

      options = store.send(:upsert_options, connection)

      refute_includes options.keys, :unique_by
    end

    def test_write_multi_keeps_unique_by_when_the_connection_supports_a_conflict_target
      connection = Class.new { def supports_insert_conflict_target? = true }.new

      options = store.send(:upsert_options, connection)

      assert_includes options.keys, :unique_by
    end

    private

    def build_store(namespace: "translation-diff", ttl: 604_800)
      TranslationDiff::ActiveRecordCacheStore.new(namespace: namespace, ttl: ttl,
                                                  table_name: "translation_diff_translations")
    end

    def expire(store, key)
      store.write(key, key)
      store.model.where(key_digest: digest_of(key)).update_all(expires_at: Time.now.utc - 1)
    end
  end
else
  class ActiveRecordCacheStoreTest < Minitest::Test
    def test_active_record_is_unavailable
      skip "active_record could not be loaded on this Ruby; the SQL cache store suite is skipped"
    end
  end
end
