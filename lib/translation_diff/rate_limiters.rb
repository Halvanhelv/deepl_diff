# Rate limiters, by name; assigning an object to `config.rate_limiter` bypasses this entirely.
module TranslationDiff::RateLimiters
  def self.register(name, klass) = registry.register(name, klass)
  def self.build(name, config) = registry.build(name, config)
  def self.registered?(name) = registry.registered?(name)
  def self.names = registry.names
  def self.classes = registry.classes
  def self.registry = @registry ||= TranslationDiff::Registry.new("rate limiter")
end
