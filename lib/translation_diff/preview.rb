# What a #translate call would do without doing it: sentences it would send, sentences already cached, their
# size, and characters -- the total the translate event itself reports, the denominator sendable_characters needs.
TranslationDiff::Preview = Data.define(:sendable_sentences, :cached_sentences, :sendable_characters, :characters)
