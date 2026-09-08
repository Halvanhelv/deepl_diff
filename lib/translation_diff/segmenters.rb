# frozen_string_literal: true

module TranslationDiff::Segmenters
  # Segmenters, by name. `config.segmenter = :simple` resolves through here.
  def self.registry = @registry ||= TranslationDiff::Registry.new("segmenter")
end
