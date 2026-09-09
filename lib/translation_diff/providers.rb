# frozen_string_literal: true

# Translation providers, by name. This is the one registry that does more
# than look a class up: registering a provider also declares that provider's
# configuration options, which is what keeps names like `deepl_api_key` out
# of TranslationDiff::Configuration and out of this library's core.
#
#   TranslationDiff::Providers.register(:acme, AcmeProvider)
#
#   TranslationDiff.configure do |config|
#     config.provider = :acme
#     config.acme_api_key = ENV["ACME_API_KEY"]
#   end
#
# Nothing in lib/ changes to make that work.
module TranslationDiff::Providers
  class << self
    # Options are declared before the registry entry is written, so a
    # provider whose option names collide with another's raises without
    # having replaced anything under `name`.
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
