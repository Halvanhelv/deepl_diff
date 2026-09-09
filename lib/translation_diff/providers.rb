# frozen_string_literal: true

# Translation providers, by name; registering one also declares its configuration options.
module TranslationDiff::Providers
  class << self
    # Options are declared before the registry entry is written, so a name collision raises without replacing.
    def register(name, klass)
      unless klass < TranslationDiff::Provider
        raise TranslationDiff::InvalidProviderError,
              "#{klass} cannot be registered as a provider: it does not inherit " \
              "TranslationDiff::Provider. The base class supplies the transport, the " \
              "configuration check and the capability defaults, so a provider that " \
              "skips it has none of them."
      end

      TranslationDiff::Configuration.register_provider_options(klass.configuration_options, klass)
      registry.register(name, klass)
    end

    def build(name, config)
      registry.build(name, config).tap { |provider| provider.name = name.to_sym }
    end

    def registered?(name) = registry.registered?(name)
    def names = registry.names
    def registry = @registry ||= TranslationDiff::Registry.new("provider")
  end
end
