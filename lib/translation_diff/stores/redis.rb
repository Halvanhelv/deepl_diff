class TranslationDiff::Stores::Redis
  ONE_WEEK = 60 * 60 * 24 * 7
  DEFAULT_NAMESPACE = "translation-diff".freeze

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

  # A non-positive or nil timeout means never expires, the same rule the SQL store applies to cache_ttl.
  def write(key, value)
    redis { |redis| write_one(redis, key, value) }
  end

  def write_multi(pairs)
    return pairs if pairs.empty?

    redis { |redis| redis.pipelined { |p| pairs.each { |key, value| write_one(p, key, value) } } }
    pairs
  end

  private

  attr_reader :connection_pool, :timeout, :namespace

  def redis
    connection_pool.with do |redis|
      yield ::Redis::Namespace.new(namespace, redis: redis)
    end
  end

  def write_one(redis, key, value)
    expiring? ? redis.setex(key, timeout, value) : redis.set(key, value)
  end

  def expiring? = timeout.is_a?(Numeric) && timeout.positive?
end

TranslationDiff::Stores.register(:redis, TranslationDiff::Stores::Redis)
