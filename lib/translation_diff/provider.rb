# Connects this library to one translation service; knows nothing about HTTP itself -- that's HTTPProvider.
class TranslationDiff::Provider
  # A subclass that forgets to declare capabilities under-promises, not over-promises: smaller batches, not silent risk.
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

  def translate(_request) = raise NotImplementedError, "#{self.class} must implement #translate"

  # Only called when `capabilities.detects_language?`.
  def detect(_text) = raise NotImplementedError, "#{self.class} must implement #detect"

  # Raising when never stamped, rather than falling back to "", is deliberate: "" would merge namespaces silently.
  def cache_key
    return name.to_s unless name.nil?

    raise TranslationDiff::Error,
          "#{self.class} has no cache key: it was instantiated directly instead of being " \
          "built through the registry. Build it through TranslationDiff::Providers.build, " \
          "or give #{self.class} its own #cache_key."
  end

  class << self
    def configuration_options = []

    # Checked once, at build time, so a caller learns what to set before a vendor's own exception does.
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
