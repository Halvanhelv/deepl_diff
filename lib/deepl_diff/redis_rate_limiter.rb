# frozen_string_literal: true

class DeepLDiff::RedisRateLimiter
  extend Dry::Initializer

  class RateLimitExceeded < StandardError; end

  param :connection_pool
  param :threshold, default: proc { 8000 }
  param :interval,  default: proc { 60 }

  option :namespace, default: proc { DeepLDiff::CACHE_NAMESPACE }

  def check(size)
    connection_pool.with do |redis|
      rate_limit = Ratelimit.new(namespace, redis: redis)
      raise RateLimitExceeded if rate_limit.exceeded?("call", threshold: threshold, interval: interval)

      rate_limit.add size
    end
  end
end
