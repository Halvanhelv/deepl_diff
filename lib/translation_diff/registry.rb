# frozen_string_literal: true

# Maps a short symbol to a class that knows how to build itself from a
# Configuration. Three of these exist -- providers, cache stores and
# segmenters -- so that every extension option in this library can accept
# either a symbol naming a built-in or an object the caller supplies.
#
# The only thing the three kinds have in common is that a registered class
# answers `build(config)`. That is deliberately the whole contract.
class TranslationDiff::Registry
  # `kind` appears in the error message for an unknown name, so it should be
  # the singular noun a reader would use: "provider", "cache store".
  def initialize(kind)
    @kind = kind
    @entries = {}
  end

  def register(name, klass)
    @entries[name.to_sym] = klass
  end

  def build(name, config)
    fetch(name).build(config)
  end

  def registered?(name) = @entries.key?(name.to_sym)

  def names = @entries.keys

  private

  def fetch(name)
    @entries.fetch(name.to_sym) do
      raise TranslationDiff::Error,
            "Unknown #{@kind} #{name.to_sym.inspect}. Registered: #{names.join(', ')}"
    end
  end
end
