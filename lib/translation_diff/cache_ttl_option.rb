# Prepended onto Configuration: nil sticks here as "never expires", unlike the generic option rule.
module TranslationDiff::CacheTtlOption
  NEVER_ASSIGNED = Object.new.freeze

  def initialize
    @cache_ttl = NEVER_ASSIGNED
    super
  end

  # A non-positive number folds into nil too -- a TTL of zero or less can never keep a row.
  def cache_ttl=(value)
    value = nil if value.is_a?(String) && value.strip.empty?
    value = coerce_ttl(value) if value.is_a?(String)
    @cache_ttl = value.is_a?(Numeric) && value <= 0 ? nil : value
  end

  def cache_ttl
    @cache_ttl.equal?(NEVER_ASSIGNED) ? self.class.defaults[:cache_ttl] : @cache_ttl
  end

  private

  # An ENV var arrives as a String; coerced here so Time.now.utc + @ttl never meets a bare String mid-translation.
  def coerce_ttl(value)
    Integer(value)
  rescue ArgumentError, TypeError
    raise TranslationDiff::Error, "cache_ttl must be a number of seconds (got #{value.inspect})"
  end
end
