# Maps a symbol to a class that builds itself from a Configuration; the whole contract is answering `build(config)`.
class TranslationDiff::Registry
  # `kind` appears in the unknown-name error message, so it should be a singular noun: "provider".
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
