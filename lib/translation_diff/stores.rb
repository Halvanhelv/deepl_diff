# frozen_string_literal: true

# Cache stores, by name. `config.cache = :redis` resolves through here;
# assigning an object bypasses it entirely.
TranslationDiff::Stores = TranslationDiff::Registry.new("cache store")
