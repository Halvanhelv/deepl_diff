# frozen_string_literal: true

class DeepLDiff::Cache
  extend Dry::Initializer

  param :from
  param :to

  def cached_and_missing(values)
    keys = values.map { |v| key(v) }
    cached = cache_store.read_multi(keys)
    missing = values.map.with_index { |v, i| v if cached[i].nil? }.compact

    [cached, missing]
  end

  def store(values, cached, updates)
    cached.map.with_index do |value, index|
      value || store_value(values[index], updates.shift)
    end
  end

  private

  def store_value(value, translation)
    cache_store.write(key(value), translation)
    translation
  end

  def key(value)
    hash = Digest::MD5.hexdigest(value.strip) # No matter how much spaces
    "#{from}:#{to}:#{hash}"
  end

  def cache_store
    DeepLDiff.cache_store
  end
end
