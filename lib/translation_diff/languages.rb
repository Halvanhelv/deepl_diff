# What each provider translates, captured from the vendor and shipped; unknown means no opinion, never a refusal.
module TranslationDiff::Languages
  DIRECTORY = File.expand_path("../../data/languages", __dir__).freeze
  # Derived from the directory itself: shipping a new file makes it load without editing this list too.
  SHIPPED = Dir.children(DIRECTORY).grep(/\.json\z/).map { |file| File.basename(file, ".json").to_sym }.sort.freeze
  # Amazon needs AWS credentials most maintainers lack; LibreTranslate's list is one private instance's own.
  NOT_SHIPPED = %i[amazon libretranslate].freeze

  class << self
    # nil, not false: a provider we ship no data for must never refuse a pair.
    def supports?(provider, from:, to:)
      set = self.for(provider)
      return nil if set.nil? # rubocop:disable Style/ReturnNilInPredicateMethodDefinition

      set.supports_source?(from) && set.supports_target?(to)
    end

    def for(provider)
      name = provider.to_s
      return nil unless SHIPPED.include?(name.to_sym)

      sets[name] ||= Set.load(File.join(DIRECTORY, "#{name}.json"))
    end

    private

    # Loaded on first use: six JSON files read at require time would slow every application that never validates.
    def sets = @sets ||= {}
  end
end
