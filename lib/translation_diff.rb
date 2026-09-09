# frozen_string_literal: true

require "cgi/escape"
require "digest/md5"
require "forwardable"
require "stringio"

require "ox"

require "translation_diff/version"
require "translation_diff/error"
require "translation_diff/errors"
require "translation_diff/capabilities"
require "translation_diff/translation/usage"
require "translation_diff/translation/request"
require "translation_diff/translation/response"
require "translation_diff/registry"
require "translation_diff/configuration"
require "translation_diff/configuration/provider_option_owners"

require "translation_diff/provider"
require "translation_diff/http_provider"
require "translation_diff/providers"
require "translation_diff/providers/null"

# DeepL and Google still wrap their vendor SDKs directly instead of
# inheriting Provider -- Tasks 4 and 5 port them. Providers.register now
# raises for exactly that shape of class, which would otherwise take this
# entire require chain, and therefore every caller of this library, down
# with it before either provider is ever used. Until they are ported,
# `:deepl` and `:google` are simply absent from the registry; requesting
# either through TranslationDiff::Providers.build raises the ordinary
# "unknown provider" error instead. The rescue names InvalidProviderError
# specifically, not the generic Error, so it catches only "this class is
# the wrong shape": an option-name collision (also a TranslationDiff::Error,
# raised by ProviderOptionOwners) is a real bug rather than an expected
# transitional state, and must still take the require chain down.
begin
  require "translation_diff/providers/deepl"
rescue TranslationDiff::InvalidProviderError
  nil
end

begin
  require "translation_diff/providers/google"
rescue TranslationDiff::InvalidProviderError
  nil
end

require "translation_diff/segmenters"
require "translation_diff/segmenters/simple"
require "translation_diff/segmenters/pragmatic"
require "translation_diff/tokenizer"
require "translation_diff/linearizer"
require "translation_diff/chunker"
require "translation_diff/spacing"
require "translation_diff/cache"
require "translation_diff/stores"
require "translation_diff/memory_cache_store"
require "translation_diff/redis_cache_store"
require "translation_diff/redis_rate_limiter"
require "translation_diff/instrumentation"
require "translation_diff/request"
require "translation_diff/context"

module TranslationDiff
  class << self
    def config = @config ||= Configuration.new

    def configure = yield(config)

    # Tests need this, and without it one test's configuration leaks into
    # every test that runs after it.
    def reset! = @config = nil

    # An isolated copy of the configuration with the same entry point, for
    # per-tenant or per-request settings. The global configuration is left
    # alone.
    #
    #   tenant = TranslationDiff.context { |c| c.deepl_api_key = key }
    #   tenant.translate("Hello.", from: "en", to: "ru")
    def context(&) = Context.new(config.copy.tap(&))

    # `provider:` and `config:` are reserved; every other keyword is
    # forwarded to the provider untouched.
    def translate(values, from: nil, to: nil, provider: nil, **)
      Request.new(values, from: from, to: to, provider: provider, config: config, **).call
    end
  end
end
