require "cgi/escape"
require "digest/md5"
require "digest/sha2"
require "forwardable"
require "securerandom"
require "stringio"

require "ox"

require "translation_diff/version"
require "translation_diff/error"
require "translation_diff/errors"
require "translation_diff/redaction"
require "translation_diff/capabilities"
require "json"
require "translation_diff/languages"
require "translation_diff/languages/set"
require "translation_diff/languages/refresh"
require "translation_diff/translation/usage"
require "translation_diff/translation/request"
require "translation_diff/translation/response"
require "translation_diff/registry"
require "translation_diff/document"
require "translation_diff/leaves"
require "translation_diff/markup"
require "translation_diff/segment"
require "translation_diff/batch"
require "translation_diff/fragment"
require "translation_diff/passage"
require "translation_diff/sentence_cache"
require "translation_diff/cache_ttl_option"
require "translation_diff/cache_guard_options"
require "translation_diff/configuration"
require "translation_diff/configuration/provider_option_owners"

require "translation_diff/provider"
require "translation_diff/http_provider"
require "translation_diff/providers"
require "translation_diff/providers/null"

require "translation_diff/providers/deepl"
require "translation_diff/providers/google"
require "translation_diff/providers/azure"
require "translation_diff/providers/modernmt"
require "translation_diff/providers/libretranslate"
require "translation_diff/providers/amazon"

require "translation_diff/segmenters"
require "translation_diff/segmenters/simple"
require "translation_diff/segmenters/pragmatic"
require "translation_diff/stores"
require "translation_diff/memory_cache_store"
require "translation_diff/redis_cache_store"
require "translation_diff/active_record_support"
require "translation_diff/active_record_cache_store"
require "translation_diff/rate_limiters"
require "translation_diff/redis_rate_limiter"
require "translation_diff/active_record_rate_limiter"
require "translation_diff/instrumentation"
require "translation_diff/call_preparation"
require "translation_diff/dispatcher"
require "translation_diff/translator"
require "translation_diff/preview"
require "translation_diff/previewer"
require "translation_diff/context"

# Only when a host application has already loaded Rails -- never required unconditionally, so a non-Rails
# application never pays for it, and the gem's own suite exercises this same guarded require, not a shortcut.
require "translation_diff/railtie" if defined?(Rails::Railtie)

module TranslationDiff
  class << self
    def config = @config ||= Configuration.new

    def configure = yield(config)

    # Without this, one test's configuration leaks into every test that runs after it.
    def reset! = @config = nil

    # An isolated copy of the configuration with the same entry point, for per-tenant settings.
    def context(&) = Context.new(config.copy.tap(&))

    # `provider:`, `config:` and `assume_supported:` are reserved; every other keyword is forwarded to the provider.
    def translate(values, from: nil, to: nil, provider: nil, assume_supported: false, **)
      Translator.new(values, from: from, to: to, provider: provider, config: config,
                             assume_supported: assume_supported, **).call
    end

    # Answers what `translate` would do to `values`, without calling a provider or writing anything.
    def preview(values, from: nil, to: nil, provider: nil, assume_supported: false, **)
      Previewer.new(values, from: from, to: to, provider: provider, config: config,
                            assume_supported: assume_supported, **).call
    end
  end
end
