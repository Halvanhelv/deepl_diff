# frozen_string_literal: true

# Tracks which provider declared each option; two silently sharing one accessor would leak a credential.
class TranslationDiff::Configuration::ProviderOptionOwners
  def initialize
    @owners = {}
  end

  # All-or-nothing: recording key by key would attribute earlier keys to a provider that then failed.
  def claim(keys, provider)
    validate!(keys, provider)
    keys.each { |key| @owners[key] = provider }
  end

  private

  def validate!(keys, provider)
    keys.each { |key| conflict!(key, provider) unless available?(key, provider) }
  end

  def available?(key, provider)
    owner = @owners[key]
    owner.nil? || same_provider?(owner, provider)
  end

  # `<=>` is non-nil exactly when both sit on one inheritance chain -- also true if `provider` isn't a Module.
  def same_provider?(owner, provider)
    owner.equal?(provider) ||
      (!owner.name.nil? && owner.name == provider.name) ||
      !(provider <=> owner).nil?
  end

  def conflict!(key, provider)
    owner = @owners[key]
    raise TranslationDiff::Error,
          "#{provider} declares the configuration option #{key.inspect}, which #{owner} " \
          "already declared. Provider options share one namespace on " \
          "TranslationDiff::Configuration: two providers declaring the same name would " \
          "share one accessor, so a credential set for one would be handed to the other. " \
          "Prefix the option with the provider's own name."
  end
end
