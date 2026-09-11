require "test_helper"

class ProvidersTest < Minitest::Test
  # Defined entirely outside this library, to prove adding a translation service requires no change to lib/.
  class AcmeProvider < TranslationDiff::Provider
    def self.configuration_options = %i[acme_token]

    def self.capabilities
      TranslationDiff::Capabilities.new(
        max_request_size: 1_000, max_batch_size: 10, max_text_size: nil,
        html: :none, notranslate: false, detects_language: false, reports_billing: false
      )
    end

    def translate(request)
      TranslationDiff::Translation::Response.build(
        request: request,
        texts: request.texts.map { |text| "#{config.acme_token}:#{request.from}-#{request.to}:#{text}" }
      )
    end
  end

  # Registering the second must raise rather than hand it the first one's accessor.
  class ConflictingProviderA < TranslationDiff::Provider
    def self.configuration_options = %i[shared_provider_token]
  end

  class ConflictingProviderB < TranslationDiff::Provider
    def self.configuration_options = %i[shared_provider_token]
  end

  # A subclass wanting AcmeProvider's own option.
  class SubclassOfAcmeProvider < AcmeProvider; end

  # PartialB would declare :partial_own_key successfully if checked eagerly, but conflicts on its second.
  class PartialProviderA < TranslationDiff::Provider
    def self.configuration_options = %i[partial_shared_key]
  end

  class PartialProviderB < TranslationDiff::Provider
    def self.configuration_options = %i[partial_own_key partial_shared_key]
  end

  class PartialProviderC < TranslationDiff::Provider
    def self.configuration_options = %i[partial_own_key]
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
    request = TranslationDiff::Translation::Request.new(texts: %w[hi], from: :en, to: :ru)

    assert_equal ["T:en-ru:hi"], provider.translate(request).texts
  end

  def test_the_registered_name_becomes_the_cache_key
    assert_equal "acme", TranslationDiff::Providers.build(:acme, @config).cache_key
  end

  def test_the_built_in_providers_are_registered
    assert TranslationDiff::Providers.registered?(:null)
    assert TranslationDiff::Providers.registered?(:deepl)
    assert TranslationDiff::Providers.registered?(:google)
  end

  def test_null_keeps_its_own_cache_key
    assert_equal "null", TranslationDiff::Providers.build(:null, @config).cache_key
  end

  # The one seam Translator and Previewer both resolve a provider through.
  def test_resolve_with_nil_returns_the_configured_provider
    @config.provider = :acme

    assert_instance_of AcmeProvider, TranslationDiff::Providers.resolve(nil, @config)
  end

  def test_resolve_with_a_name_builds_that_provider
    assert_instance_of AcmeProvider, TranslationDiff::Providers.resolve(:acme, @config)
  end

  def test_resolve_with_an_object_uses_it_as_is
    instance = TranslationDiff::Providers.build(:acme, @config)

    assert_same instance, TranslationDiff::Providers.resolve(instance, @config)
  end

  # A blank cache_key would file a provider's translations in every other provider's namespace.
  class BlankCacheKeyProvider < TranslationDiff::Provider
    def cache_key = "   "
  end

  def test_resolve_refuses_a_provider_whose_cache_key_is_blank
    instance = BlankCacheKeyProvider.new(@config)

    error = assert_raises(TranslationDiff::InvalidProviderError) { TranslationDiff::Providers.resolve(instance, @config) }

    assert_match(/must define #cache_key/, error.message)
  end

  # A defensive double `require` and a Rails reload both re-run registration; redeclaring must stay silent.
  def test_registering_the_same_provider_twice_is_not_a_conflict
    TranslationDiff::Providers.register(:acme, AcmeProvider)

    assert_includes TranslationDiff::Configuration.options, :acme_token
  end

  # Rails reloading yields a *new* class object under the same constant, so identity alone would raise.
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

  # Without this guard, ConflictingProviderB would be handed the accessor and value ConflictingProviderA set.
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

  # Used to raise: a subclass claiming its inherited option looked identical to an unrelated class claiming it.
  def test_a_subclass_of_a_registered_provider_may_be_registered
    TranslationDiff::Providers.register(:acme_subclass, SubclassOfAcmeProvider)

    assert TranslationDiff::Providers.registered?(:acme_subclass)
    assert_includes TranslationDiff::Configuration.options, :acme_token
  end

  # The relaxation is specific to an inheritance relationship; an unrelated class is still refused.
  def test_an_unrelated_class_claiming_a_subclassable_option_still_raises
    unrelated = Class.new(TranslationDiff::Provider) do
      def self.configuration_options = %i[acme_token]
    end

    error = assert_raises(TranslationDiff::Error) do
      TranslationDiff::Providers.register(:acme_unrelated, unrelated)
    end

    assert_match(/acme_token/, error.message)
    refute TranslationDiff::Providers.registered?(:acme_unrelated)
  end

  # Registration must be all-or-nothing: a conflict on the second option must not leave the first declared.
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

  # A duck-typed object cannot be given the transport, the requirement check, or the capability defaults.
  def test_registering_a_class_that_is_not_a_provider_raises
    not_a_provider = Class.new do
      def self.configuration_options = []
      def self.build(_config) = new
    end

    error = assert_raises(TranslationDiff::InvalidProviderError) do
      TranslationDiff::Providers.register(:impostor, not_a_provider)
    end

    assert_match(/TranslationDiff::Provider/, error.message)
    refute TranslationDiff::Providers.registered?(:impostor)
  end

  # `klass < Provider` raised NoMethodError for an instance -- the first thing someone writing a provider hits.
  def test_registering_an_instance_rather_than_a_class_raises_the_registry_error
    instance = TranslationDiff::Providers::Null.new(TranslationDiff::Configuration.new)

    error = assert_raises(TranslationDiff::InvalidProviderError) do
      TranslationDiff::Providers.register(:impostor_instance, instance)
    end

    assert_match(/TranslationDiff::Provider/, error.message)
    refute TranslationDiff::Providers.registered?(:impostor_instance)
  end

  # `klass < Provider` raised ArgumentError for a non-Module, and NoMethodError for nil or a symbol.
  def test_registering_a_non_module_raises_the_registry_error
    [nil, :deepl, 42, Object.new].each do |value|
      assert_raises(TranslationDiff::InvalidProviderError) do
        TranslationDiff::Providers.register(:impostor_value, value)
      end
    end

    refute TranslationDiff::Providers.registered?(:impostor_value)
  end

  # The message names the class, never the object: an arbitrary #to_s renders its own content or an address.
  def test_the_registry_error_names_the_class_and_not_the_object
    secret = Struct.new(:token).new("s3cret")

    error = assert_raises(TranslationDiff::InvalidProviderError) do
      TranslationDiff::Providers.register(:impostor_secret, secret)
    end

    refute_match(/s3cret/, error.message)
  end

  # A caller rescuing "this class cannot be a provider" must not also accidentally swallow an option collision.
  def test_an_option_collision_raises_the_generic_error_not_the_invalid_provider_one
    TranslationDiff::Providers.register(:collision_a, ConflictingProviderA)

    error = assert_raises(TranslationDiff::Error) do
      TranslationDiff::Providers.register(:collision_b, ConflictingProviderB)
    end

    refute_kind_of TranslationDiff::InvalidProviderError, error
  end

  private

  def reloadable_provider_class
    Class.new(TranslationDiff::Provider) do
      def self.configuration_options = %i[reloaded_token]
    end
  end
end
