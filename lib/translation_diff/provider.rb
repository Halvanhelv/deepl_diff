# frozen_string_literal: true

# A Provider connects this library to one translation service. It knows where
# to talk, who it is, and what it can do. It knows nothing about HTTP -- that
# is HTTPProvider, which most providers inherit instead. Inheriting Provider
# directly is for services reached some other way: Amazon, whose requests are
# signed rather than merely headed, and an LLM-backed provider that delegates
# to another gem.
#
# Subclass, declare the options you need, then register:
#
#   class Acme < TranslationDiff::Provider
#     def self.configuration_options = %i[acme_api_key]
#     def self.configuration_requirements = %i[acme_api_key]
#     def self.capabilities = TranslationDiff::Capabilities.new(...)
#
#     def translate(request) = TranslationDiff::Translation::Response.build(...)
#   end
#
#   TranslationDiff::Providers.register(:acme, Acme)
class TranslationDiff::Provider
  # What a provider can do when it says nothing: the least capable thing that
  # can still translate. A subclass that forgets to declare its capabilities
  # therefore under-promises rather than over-promises -- the failure mode is
  # smaller batches, not a rejected request or silently unprotected content.
  DEFAULT_CAPABILITIES = TranslationDiff::Capabilities.new(
    max_request_size: 1_000, max_batch_size: 1, max_text_size: nil,
    html: :none, notranslate: false, detects_language: false, reports_billing: false
  ).freeze

  # Stamped by the registry at build time. See #cache_key.
  attr_accessor :name

  attr_reader :config

  def initialize(config)
    @config = config
    ensure_configured!
  end

  # Translate a Translation::Request, return a Translation::Response.
  def translate(_request) = raise NotImplementedError, "#{self.class} must implement #translate"

  # Return the source language of a sample of text, lowercased. Only called
  # when `capabilities.detects_language?`.
  def detect(_text) = raise NotImplementedError, "#{self.class} must implement #detect"

  # The segment of every cache key that keeps one provider's translations from
  # being served for another. Raising when the provider was never stamped --
  # rather than falling back to "" -- is deliberate: an empty segment would
  # merge two providers' namespaces silently.
  def cache_key
    return name.to_s unless name.nil?

    raise TranslationDiff::Error,
          "#{self.class} has no cache key: it was instantiated directly instead of being " \
          "built through the registry. Build it through TranslationDiff::Providers.build, " \
          "or give #{self.class} its own #cache_key."
  end

  class << self
    def configuration_options = []

    # The subset of configuration_options without which this provider cannot
    # work. Checked once, at build time, so a caller learns what to set before
    # any request is attempted rather than from a vendor's own exception.
    def configuration_requirements = []

    def capabilities = DEFAULT_CAPABILITIES

    def build(config) = new(config)
  end

  private

  def ensure_configured!
    missing = self.class.configuration_requirements.reject { |key| config.public_send(key) }
    return if missing.empty?

    raise TranslationDiff::ConfigurationError,
          "Provider #{self.class} is missing #{missing.join(', ')}. " \
          "Set #{missing.size == 1 ? 'it' : 'them'} in TranslationDiff.configure."
  end
end
