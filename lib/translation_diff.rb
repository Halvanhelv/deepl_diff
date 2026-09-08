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

require "translation_diff/adapters"
require "translation_diff/adapters/null"
require "translation_diff/adapters/deepl"
require "translation_diff/segmenters"
require "translation_diff/segmenters/simple"
require "translation_diff/segmenters/pragmatic"
require "translation_diff/tokenizer"
require "translation_diff/linearizer"
require "translation_diff/chunker"
require "translation_diff/spacing"
require "translation_diff/cache"
require "translation_diff/redis_cache_store"
require "translation_diff/redis_rate_limiter"
require "translation_diff/request"

module TranslationDiff
  class << self
    attr_accessor :api, :cache_store, :rate_limiter
    attr_writer :segmenter

    def translate(values, from: nil, to: nil, **)
      Request.new(values, from: from, to: to, **).call
    end

    def segmenter
      @segmenter ||= TranslationDiff::Segmenters::Pragmatic.new
    end
  end

  CACHE_NAMESPACE = "translation-diff"
end
