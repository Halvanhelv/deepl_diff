# frozen_string_literal: true

require "ox"
require "punkt-segmenter"
require "dry/initializer"
require "deepl"

require "deepl_diff/version"
require "deepl_diff/tokenizer"
require "deepl_diff/linearizer"
require "deepl_diff/chunker"
require "deepl_diff/spacing"
require "deepl_diff/cache"
require "deepl_diff/redis_cache_store"
require "deepl_diff/redis_rate_limiter"
require "deepl_diff/request"

module DeepLDiff
  class << self
    attr_accessor :api, :cache_store, :rate_limiter

    def translate(*args)
      Request.new(*args).call
    end
  end

  CACHE_NAMESPACE = "deepl-diff"
end
