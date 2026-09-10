require "test_helper"

class RedactionTest < ConfiguredTest
  def test_configuration_inspect_hides_every_credential_it_holds
    TranslationDiff.configure do |c|
      c.deepl_api_key = "SECRET-DEEPL-abc123:fx"
      c.amazon_secret_access_key = "SECRET-AWS-xyz789"
      c.cache_namespace = "tenant-7"
    end

    rendered = TranslationDiff.config.inspect

    refute_includes rendered, "SECRET-DEEPL-abc123:fx"
    refute_includes rendered, "SECRET-AWS-xyz789"
    assert_includes rendered, "[FILTERED]"
    assert_includes rendered, "tenant-7"
  end

  def test_a_provider_inspect_hides_the_credentials_of_the_configuration_it_holds
    TranslationDiff.configure { |c| c.deepl_api_key = "SECRET-DEEPL-abc123:fx" }
    provider = TranslationDiff::Providers.build(:deepl, TranslationDiff.config)

    rendered = provider.inspect

    refute_includes rendered, "SECRET-DEEPL-abc123:fx"
    assert_includes rendered, "deepl"
  end

  # The default #inspect of any object holding either one calls theirs, so the leak has to stop here.
  def test_an_object_holding_the_configuration_leaks_nothing_either
    TranslationDiff.configure { |c| c.deepl_api_key = "SECRET-DEEPL-abc123:fx" }
    context = TranslationDiff.context { |c| c.cache = :memory }

    refute_includes context.inspect, "SECRET-DEEPL-abc123:fx"
  end

  # Derived from the registry, so a provider registered later is covered without anyone remembering.
  # The option name must not match SENSITIVE itself, or the test would pass even with the registry union deleted.
  def test_the_filtered_list_covers_a_provider_registered_afterwards
    klass = Class.new(TranslationDiff::Provider) do
      def self.configuration_options = %i[redaction_acme_session redaction_acme_api_base]
      def self.sensitive_options = %i[redaction_acme_session]
    end
    TranslationDiff::Providers.register(:acme_redaction, klass)
    TranslationDiff.configure { |c| c.redaction_acme_session = "SECRET-ACME-000" }

    refute_includes TranslationDiff.config.inspect, "SECRET-ACME-000"
  end

  def test_a_base_url_is_not_a_credential_and_stays_visible
    TranslationDiff.configure { |c| c.libretranslate_api_base = "http://localhost:5000" }

    assert_includes TranslationDiff.config.inspect, "http://localhost:5000"
  end

  # No ENV default exists for this one, so it is truly unset everywhere, not just on a laptop without the var.
  def test_an_unset_option_is_not_rendered_at_all
    refute_includes TranslationDiff.config.inspect, "azure_api_key"
  end

  # The regex can't catch this name; the provider has to say so itself, and Redaction has to ask it.
  def test_a_provider_overriding_sensitive_options_hides_a_name_the_regex_cannot_match
    klass = Class.new(TranslationDiff::Provider) do
      def self.configuration_options = %i[acme_cookie]
      def self.sensitive_options = %i[acme_cookie]
    end
    TranslationDiff::Providers.register(:acme_cookie_provider, klass)
    TranslationDiff.configure { |c| c.acme_cookie = "SECRET-SESSION-COOKIE-VALUE" }

    refute_includes TranslationDiff.config.inspect, "SECRET-SESSION-COOKIE-VALUE"
  end

  # Set only through its ENV-backed default, so no ivar exists; inspect must still filter it, not skip it.
  def test_an_option_set_only_through_its_env_default_is_still_filtered
    ENV["DEEPL_AUTH_KEY"] = "SECRET-DEEPL-FROM-ENV"

    assert_includes TranslationDiff.config.inspect, "[FILTERED]"
    refute_includes TranslationDiff.config.inspect, "SECRET-DEEPL-FROM-ENV"
  ensure
    ENV.delete("DEEPL_AUTH_KEY")
  end

  # Heroku, Upstash, Redis Cloud, Aiven and ElastiCache all put the credential inline in this URL.
  def test_a_redis_url_has_its_password_redacted_but_stays_readable
    TranslationDiff.configure do |c|
      c.redis_url = "rediss://default:AbCdEf-SUPER-SECRET-TOKEN@cache.example.upstash.io:6379"
    end

    rendered = TranslationDiff.config.inspect

    refute_includes rendered, "AbCdEf-SUPER-SECRET-TOKEN"
    assert_includes rendered, "[FILTERED]"
    assert_includes rendered, "default"
    assert_includes rendered, "cache.example.upstash.io:6379"
  end

  # A provider's *_api_base can carry basic-auth credentials the same way redis_url does.
  def test_a_provider_api_base_with_basic_auth_has_its_password_redacted
    TranslationDiff.configure { |c| c.libretranslate_api_base = "https://user:hunter2@translate.example.com" }

    rendered = TranslationDiff.config.inspect

    refute_includes rendered, "hunter2"
    assert_includes rendered, "translate.example.com"
  end

  # An inspect that blows up on a bad value is worse than a verbose one.
  def test_a_malformed_url_like_option_does_not_raise_from_inspect
    TranslationDiff.configure { |c| c.libretranslate_api_base = "http://[not-a-valid-host" }

    rendered = TranslationDiff.config.inspect

    assert_includes rendered, "libretranslate_api_base"
  end
end
