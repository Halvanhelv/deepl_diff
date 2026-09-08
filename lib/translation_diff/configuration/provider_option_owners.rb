# frozen_string_literal: true

# Tracks which provider declared each provider-specific configuration option
# name, so `Configuration.option` -- which returns early on a name it
# already knows -- never lets two providers silently share one accessor. If
# it did, a credential set for one provider would be handed to the other;
# that is a packaging conflict a human has to resolve, so #claim raises and
# names both.
#
# The same provider re-declaring its own options is not a conflict: a
# defensive double `require` and a Rails development reload both re-run
# registration, and a reload yields a *new* class object for the same
# constant, which is why identity is not the only test. Nor is a subclass of
# the declaring provider a conflict -- a provider subclassed to point it at
# a different host or account is meant to share its parent's options.
class TranslationDiff::Configuration::ProviderOptionOwners
  def initialize
    @owners = {}
  end

  # All-or-nothing: every key is checked for a conflict before any of them
  # is recorded as owned. Checking and recording key by key would leave the
  # options before a conflicting one already attributed to a provider that
  # then failed to register -- so a later, legitimate registration of one
  # of those names would be refused, blaming a provider that was never
  # registered.
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

  # `<=>` returns non-nil (0 for equal, -1/1 for either direction) exactly
  # when `owner` and `provider` sit on one inheritance chain, and nil for
  # two unrelated classes -- which is also how it answers "or is not a
  # Module at all", since only Modules define `<=>` this way.
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
