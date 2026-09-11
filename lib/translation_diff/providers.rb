# Translation providers, by name; registering one also declares its configuration options.
module TranslationDiff::Providers
  # Said once, so a provider refused by name, by class or as an object is refused in the same words.
  CONTRACT = "The base class supplies the transport, the configuration check and the " \
             "capability defaults, so a provider that skips it has none of them.".freeze

  class << self
    # Options are declared before the registry entry is written, so a name collision raises without replacing.
    def register(name, klass)
      ensure_provider_class!(klass)
      TranslationDiff::Configuration.register_provider_options(klass.configuration_options, klass)
      registry.register(name, klass)
    end

    # Guards registration. `klass < Provider` alone raises NoMethodError for an instance or a non-Module.
    def ensure_provider_class!(klass)
      return klass if klass.is_a?(Class) && klass < TranslationDiff::Provider

      raise TranslationDiff::InvalidProviderError,
            "#{describe(klass)} cannot be registered as a provider: the registry takes a " \
            "class inheriting TranslationDiff::Provider. #{CONTRACT}"
    end

    # Guards the other two ways a provider arrives: assigned to config.provider, or passed as `provider:`.
    def ensure_provider!(instance)
      return instance if instance.is_a?(TranslationDiff::Provider)

      raise TranslationDiff::InvalidProviderError,
            "#{describe(instance)} cannot be used as a provider: it does not inherit " \
            "TranslationDiff::Provider. #{CONTRACT}"
    end

    def build(name, config)
      registry.build(name, config).tap { |provider| provider.name = name.to_sym }
    end

    # The one seam Translator and Previewer both need: a provider by name, by object, or -- given nothing --
    # the configured one. The cache_key guard travels with it: a provider that skips it would file its
    # translations in every other provider's namespace, which is the one failure this method exists to prevent.
    def resolve(requested, config)
      provider = requested.nil? ? config.provider_instance : resolve_requested(requested, config)
      ensure_cache_key!(provider)
    end

    def registered?(name) = registry.registered?(name)
    def names = registry.names
    def classes = registry.classes
    def registry = @registry ||= TranslationDiff::Registry.new("provider")

    private

    # A provider arrives as a name to build, or as an object to use as it is.
    def resolve_requested(requested, config)
      return build(requested, config) if requested.is_a?(Symbol) || requested.is_a?(String)

      ensure_provider!(requested)
    end

    # The cache key names the provider in every payload too: it is the one identifier every provider must have.
    def ensure_cache_key!(provider)
      return provider unless provider.cache_key.to_s.strip.empty?

      raise TranslationDiff::InvalidProviderError,
            "#{provider.class} must define #cache_key: a blank one would file its " \
            "translations in every other provider's cache namespace."
    end

    # Never #to_s on a non-Module: an arbitrary object renders its own content, or an address.
    def describe(value) = value.is_a?(Module) ? value.to_s : "an instance of #{value.class}"
  end
end
