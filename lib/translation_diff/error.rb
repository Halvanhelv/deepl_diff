# frozen_string_literal: true

# Common ancestor for every error this gem raises. Without it, a caller who
# wants to rescue anything TranslationDiff can throw has to list four
# unrelated classes; with it, `rescue TranslationDiff::Error` is enough.
class TranslationDiff::Error < StandardError; end
