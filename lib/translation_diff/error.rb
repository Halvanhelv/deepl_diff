# Common ancestor for every error this gem raises, so `rescue TranslationDiff::Error` is enough.
class TranslationDiff::Error < StandardError; end
