# frozen_string_literal: true

class DeepLDiff::RedisCacheStore
  extend Dry::Initializer

  param :connection_pool

  option :timeout, default: proc { 60 * 60 * 24 * 7 }
  option :namespace, default: proc { DeepLDiff::CACHE_NAMESPACE }

  def read_multi(keys)
    redis { |redis| redis.mget(*keys) }
  end

  def write(key, value)
    redis { |redis| redis.setex(key, timeout, value) }
  end

  private

  def redis
    connection_pool.with do |redis|
      yield Redis::Namespace.new(namespace, redis: redis)
    end
  end
end
