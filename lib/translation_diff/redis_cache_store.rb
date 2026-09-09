# frozen_string_literal: true

class TranslationDiff::RedisCacheStore
  ONE_WEEK = 60 * 60 * 24 * 7
  DEFAULT_NAMESPACE = "translation-diff"

  def self.build(config)
    new(config.redis_pool, timeout: config.cache_ttl, namespace: config.cache_namespace)
  end

  # `connection_pool` is duck-typed to #with; neither connection_pool nor redis-namespace is a hard dependency.
  def initialize(connection_pool, timeout: ONE_WEEK, namespace: DEFAULT_NAMESPACE)
    @connection_pool = connection_pool
    @timeout = timeout
    @namespace = namespace
  end

  def read_multi(keys)
    redis { |redis| redis.mget(*keys) }
  end

  def write(key, value)
    redis { |redis| redis.setex(key, timeout, value) }
  end

  private

  attr_reader :connection_pool, :timeout, :namespace

  def redis
    connection_pool.with do |redis|
      yield Redis::Namespace.new(namespace, redis: redis)
    end
  end
end

TranslationDiff::Stores.register(:redis, TranslationDiff::RedisCacheStore)
