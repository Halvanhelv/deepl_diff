# frozen_string_literal: true

# Translation providers, by name. This is the one registry that does more
# than look a class up: registering a provider also declares that provider's
# configuration options, which is what keeps names like `deepl_api_key` out
# of TranslationDiff::Configuration and out of this library's core.
#
#   TranslationDiff::Providers.register(:google, GoogleTranslateProvider)
#
#   TranslationDiff.configure do |config|
#     config.provider = :google
#     config.google_api_key = ENV["GOOGLE_API_KEY"]
#   end
#
# Nothing in lib/ changes to make that work.
module TranslationDiff::Providers
  # Supplies the cache-key segment that keeps one provider's cached
  # translations from being served to another. A provider built through the
  # registry is stamped with its registered name and needs nothing else; a
  # provider object assigned straight to `config.provider` never passed
  # through here, so it must define #cache_key itself.
  module Naming
    attr_accessor :name

    def cache_key = name.to_s
  end

  class << self
    def register(name, klass)
      klass.include(Naming) unless klass.method_defined?(:cache_key)
      registry.register(name, klass)
      TranslationDiff::Configuration.register_provider_options(klass.configuration_options)
    end

    def build(name, config)
      registry.build(name, config).tap do |provider|
        provider.name = name.to_sym if provider.respond_to?(:name=)
      end
    end

    def registered?(name) = registry.registered?(name)
    def names = registry.names
    def registry = @registry ||= TranslationDiff::Registry.new("provider")
  end
end
