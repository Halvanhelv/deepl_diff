# frozen_string_literal: true

require "test_helper"

class ProvidersTest < Minitest::Test
  # A provider defined entirely outside this library, to prove that adding a
  # translation service requires no change to lib/.
  class AcmeProvider
    def self.configuration_options = %i[acme_token]
    def self.build(config) = new(config.acme_token)

    attr_accessor :name

    def initialize(token)
      @token = token
    end

    def translate(texts, from:, to:, **_options)
      texts.map { |text| "#{@token}:#{from}-#{to}:#{text}" }
    end

    def max_request_size = 1_000
    def max_batch_size = 10
  end

  # Two providers that both want the same option name. Registering the
  # second must raise rather than hand it the first one's accessor.
  class ConflictingProviderA
    def self.configuration_options = %i[shared_provider_token]
    def self.build(_config) = new
  end

  class ConflictingProviderB
    def self.configuration_options = %i[shared_provider_token]
    def self.build(_config) = new
  end

  # A subclass wanting AcmeProvider's own option -- subclassing a provider
  # to point it at a different host or account is an obvious thing to want.
  class SubclassOfAcmeProvider < AcmeProvider; end

  # The second-key-conflicts shape: PartialB would declare :partial_own_key
  # successfully if checked eagerly, but conflicts with PartialA's
  # :partial_shared_key on its second option.
  class PartialProviderA
    def self.configuration_options = %i[partial_shared_key]
    def self.build(_config) = new
  end

  class PartialProviderB
    def self.configuration_options = %i[partial_own_key partial_shared_key]
    def self.build(_config) = new
  end

  class PartialProviderC
    def self.configuration_options = %i[partial_own_key]
    def self.build(_config) = new
  end

  def setup
    TranslationDiff::Providers.register(:acme, AcmeProvider)
    @config = TranslationDiff::Configuration.new
    @config.acme_token = "T"
  end

  def test_registering_declares_the_providers_own_options_on_the_configuration
    assert_includes TranslationDiff::Configuration.options, :acme_token
  end

  def test_building_produces_a_working_provider
    provider = TranslationDiff::Providers.build(:acme, @config)

    assert_equal ["T:en-ru:hi"], provider.translate(["hi"], from: :en, to: :ru)
  end

  def test_the_registered_name_becomes_the_cache_key
    assert_equal "acme", TranslationDiff::Providers.build(:acme, @config).cache_key
  end

  def test_the_built_in_providers_are_registered
    assert TranslationDiff::Providers.registered?(:deepl)
    assert TranslationDiff::Providers.registered?(:null)
  end

  def test_null_keeps_its_own_cache_key
    assert_equal "null", TranslationDiff::Providers.build(:null, @config).cache_key
  end

  # A defensive double `require` and a Rails development reload both re-run
  # registration, so the same provider redeclaring its own options must stay
  # silent. #setup has already registered AcmeProvider once.
  def test_registering_the_same_provider_twice_is_not_a_conflict
    TranslationDiff::Providers.register(:acme, AcmeProvider)

    assert_includes TranslationDiff::Configuration.options, :acme_token
  end

  # Rails reloading yields a *new* class object under the same constant, so
  # identity alone would make an ordinary development reload raise.
  def test_a_reloaded_class_of_the_same_name_is_not_a_conflict
    Object.const_set(:ReloadedProvider, reloadable_provider_class)
    TranslationDiff::Providers.register(:reloaded, ReloadedProvider)
    first = ReloadedProvider

    Object.send(:remove_const, :ReloadedProvider)
    Object.const_set(:ReloadedProvider, reloadable_provider_class)
    TranslationDiff::Providers.register(:reloaded, ReloadedProvider)

    refute_same first, ReloadedProvider
    assert_includes TranslationDiff::Configuration.options, :reloaded_token
  ensure
    Object.send(:remove_const, :ReloadedProvider) if Object.const_defined?(:ReloadedProvider)
  end

  # Reproduces the credential crossing: `Configuration.option` returns early
  # on a name it already knows, so without this guard ConflictingProviderB
  # would be handed the accessor -- and the value -- ConflictingProviderA set.
  def test_a_second_provider_claiming_a_declared_option_name_raises
    TranslationDiff::Providers.register(:conflict_a, ConflictingProviderA)

    error = assert_raises(TranslationDiff::Error) do
      TranslationDiff::Providers.register(:conflict_b, ConflictingProviderB)
    end

    assert_match(/shared_provider_token/, error.message)
    assert_match(/ConflictingProviderA/, error.message)
    assert_match(/ConflictingProviderB/, error.message)
    refute TranslationDiff::Providers.registered?(:conflict_b)
  end

  # AcmeProvider (registered as :acme in #setup) owns :acme_token. A
  # subclass inherits that option and must still be registerable under its
  # own name -- this used to raise, since a subclass claiming its inherited
  # option looked identical to an unrelated class claiming a taken one.
  def test_a_subclass_of_a_registered_provider_may_be_registered
    TranslationDiff::Providers.register(:acme_subclass, SubclassOfAcmeProvider)

    assert TranslationDiff::Providers.registered?(:acme_subclass)
    assert_includes TranslationDiff::Configuration.options, :acme_token
  end

  # An unrelated class is still refused for the very option a subclass may
  # now share -- the relaxation is specific to an inheritance relationship.
  def test_an_unrelated_class_claiming_a_subclassable_option_still_raises
    unrelated = Class.new do
      def self.configuration_options = %i[acme_token]
      def self.build(_config) = new
    end

    error = assert_raises(TranslationDiff::Error) do
      TranslationDiff::Providers.register(:acme_unrelated, unrelated)
    end

    assert_match(/acme_token/, error.message)
    refute TranslationDiff::Providers.registered?(:acme_unrelated)
  end

  # Registration must be all-or-nothing: PartialProviderB conflicts on its
  # second option, so it must not leave its first option declared, owned by
  # PartialProviderB, or itself registered -- and a later, legitimate
  # provider claiming that first option name must succeed.
  def test_a_failed_registration_leaves_no_partial_option_state
    TranslationDiff::Providers.register(:partial_a, PartialProviderA)

    assert_raises(TranslationDiff::Error) do
      TranslationDiff::Providers.register(:partial_b, PartialProviderB)
    end

    refute TranslationDiff::Providers.registered?(:partial_b)
    refute_includes TranslationDiff::Configuration.options, :partial_own_key

    TranslationDiff::Providers.register(:partial_c, PartialProviderC)

    assert TranslationDiff::Providers.registered?(:partial_c)
    assert_includes TranslationDiff::Configuration.options, :partial_own_key
  end

  # A provider instantiated directly, bypassing TranslationDiff::Providers.build,
  # never gets its #name stamped. Falling back to "" there would let two such
  # providers share the same cache namespace silently, so this must raise
  # instead.
  def test_cache_key_raises_when_the_provider_was_never_built_through_the_registry
    provider = AcmeProvider.new("T")

    error = assert_raises(TranslationDiff::Error) { provider.cache_key }

    assert_match(/registry/, error.message)
  end

  private

  def reloadable_provider_class
    Class.new do
      def self.configuration_options = %i[reloaded_token]
      def self.build(_config) = new
    end
  end
end
