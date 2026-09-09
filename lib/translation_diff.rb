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
require "translation_diff/document"
require "translation_diff/markup"
require "translation_diff/segment"
require "translation_diff/batch"
require "translation_diff/fragment"
require "translation_diff/passage"
require "translation_diff/sentence_cache"
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

    # Without this, one test's configuration leaks into every test that runs after it.
    def reset! = @config = nil

    # An isolated copy of the configuration with the same entry point, for per-tenant settings.
    def context(&) = Context.new(config.copy.tap(&))

    # `provider:` and `config:` are reserved; every other keyword is forwarded to the provider.
    def translate(values, from: nil, to: nil, provider: nil, **)
      Request.new(values, from: from, to: to, provider: provider, config: config, **).call
    end
  end
end
