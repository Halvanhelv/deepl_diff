require "uri"

# Which configuration options must never be printed, decided by name rather than by a list someone maintains.
module TranslationDiff::Redaction
  SENSITIVE = /key|secret|token|password|auth|credential/
  FILTERED = "[FILTERED]".freeze

  def self.sensitive?(name) = name.to_s.match?(SENSITIVE)

  # Unioned fresh on every call, never memoised -- a provider can register after the first inspect.
  def self.declared_sensitive
    TranslationDiff::Providers.classes.flat_map(&:sensitive_options).map(&:to_sym)
  end

  # Reads through the public accessor, or an option set only through its ENV-backed default goes unnoticed.
  def self.render(config)
    declared = declared_sensitive

    TranslationDiff::Configuration.options.filter_map do |key|
      value = config.public_send(key)
      next if value.nil?

      "#{key}=#{rendered_value(key, value, declared)}"
    end
  end

  def self.rendered_value(key, value, declared)
    return FILTERED if sensitive?(key) || declared.include?(key)

    (redact_userinfo(value) || value).inspect
  end

  # redis_url and a provider's *_api_base can carry a credential inline; the host stays, only the userinfo hides.
  def self.redact_userinfo(value)
    return nil unless value.is_a?(String)

    userinfo = URI.parse(value).userinfo
    return nil unless userinfo

    user, separator, = userinfo.partition(":")
    value.sub(userinfo, separator.empty? ? FILTERED : "#{user}:#{FILTERED}")
  rescue URI::Error
    nil
  end
end
