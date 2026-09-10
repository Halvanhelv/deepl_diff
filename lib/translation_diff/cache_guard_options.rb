# Prepended onto Configuration: fails cache_prune_probability and cache_namespace at configure time, not later.
module TranslationDiff::CacheGuardOptions
  CACHE_NAMESPACE_LIMIT = 64

  # An ENV var arrives as a String; coerced here so a translate call never meets a bare String's missing #positive?.
  def cache_prune_probability=(value)
    value = nil if value.is_a?(String) && value.strip.empty?
    @cache_prune_probability = value.nil? ? nil : coerce_probability(value)
  end

  # Refused here, rather than at the first write's ActiveRecord::ValueTooLong.
  def cache_namespace=(value)
    value = nil if value.is_a?(String) && value.strip.empty?
    raise namespace_too_long(value) if value.is_a?(String) && value.length > CACHE_NAMESPACE_LIMIT

    @cache_namespace = value
  end

  private

  def coerce_probability(value)
    Float(value)
  rescue ArgumentError, TypeError
    raise TranslationDiff::Error, "cache_prune_probability must be a number between 0 and 1 (got #{value.inspect})"
  end

  def namespace_too_long(value)
    TranslationDiff::Error.new("cache_namespace must be #{CACHE_NAMESPACE_LIMIT} characters or fewer " \
                               "(got #{value.length})")
  end
end
