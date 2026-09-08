# frozen_string_literal: true

require "cgi/escape"
require "digest/md5"
require "forwardable"
require "stringio"

require "ox"

require "translation_diff/version"
require "translation_diff/error"
require "translation_diff/registry"
require "translation_diff/configuration"

require "translation_diff/providers"
require "translation_diff/providers/null"
require "translation_diff/providers/deepl"
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
