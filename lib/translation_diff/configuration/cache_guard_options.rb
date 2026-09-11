# Prepended onto Configuration: fails cache_prune_probability and cache_namespace at configure time, not later.
module TranslationDiff::Configuration::CacheGuardOptions
  CACHE_NAMESPACE_LIMIT = 64

  # An ENV var arrives as a String; coerced here so a translate call never meets a bare String's missing
  # #positive?. Handed to super so the declared writer's cache_store invalidation still runs.
  def cache_prune_probability=(value)
    value = nil if value.is_a?(String) && value.strip.empty?
    super(value.nil? ? nil : coerce_probability(value))
  end

  # Refused here, rather than at the first write's ActiveRecord::ValueTooLong.
  def cache_namespace=(value)
    value = nil if value.is_a?(String) && value.strip.empty?
    raise namespace_too_long(value) if value.is_a?(String) && value.length > CACHE_NAMESPACE_LIMIT

    super
  end

  private

  def coerce_probability(value)
    probability = Float(value)
    raise probability_out_of_range(value) unless (0..1).cover?(probability)

    probability
  rescue ArgumentError, TypeError
    raise probability_out_of_range(value)
  end

  def probability_out_of_range(value)
    TranslationDiff::Error.new("cache_prune_probability must be a number between 0 and 1 (got #{value.inspect})")
  end

  def namespace_too_long(value)
    TranslationDiff::Error.new("cache_namespace must be #{CACHE_NAMESPACE_LIMIT} characters or fewer " \
                               "(got #{value.length})")
  end
end
