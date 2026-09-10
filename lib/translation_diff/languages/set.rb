# One provider's languages as captured on a date; source and target differ, so they are kept apart.
class TranslationDiff::Languages::Set
  attr_reader :provider, :captured_at, :endpoint, :source, :target

  # ISO 639-1 macrolanguage codes callers write, mapped to the ISO 639-3 individual some vendors ship instead.
  # One-way only: a vendor listing the individual has, by definition, covered its macro; the reverse is not true.
  MACRO_ALIASES = {
    "fa" => "pes", "uz" => "uzn", "yi" => "ydd", "om" => "gaz", "qu" => "quy", "ay" => "ayr",
    "mn" => "khk", "ms" => "zsm", "lv" => "lvs", "mg" => "plt", "az" => "azj", "ps" => "pbt",
    "sw" => "swh", "ku" => "kmr", "zh" => "cmn", "ne" => "npi", "or" => "ory", "sq" => "als"
  }.freeze

  def self.load(path)
    document = parse(path)

    new(provider: document["provider"], captured_at: document["captured_at"],
        endpoint: document["endpoint"], source: document["source"], target: document["target"])
  end

  # A maintainer sees a path and the parser's own complaint instead of guessing which of the shipped files broke.
  def self.parse(path)
    JSON.parse(File.read(path))
  rescue JSON::ParserError => e
    raise TranslationDiff::Error, "#{path} is not valid JSON: #{e.message}"
  end
  private_class_method :parse

  def initialize(provider:, captured_at:, endpoint:, source:, target:)
    @provider = provider
    @captured_at = captured_at
    @endpoint = endpoint
    @source = normalise(source)
    @target = normalise(target)
    freeze
  end

  def supports_source?(code) = matches?(@source, code)
  def supports_target?(code) = matches?(@target, code)

  private

  def normalise(codes) = Array(codes).map { |code| code.to_s.downcase }.freeze

  # Primary subtag in both directions, plus a macro wanted against the individual code this provider lists for it.
  def matches?(codes, code)
    wanted = code.to_s.downcase
    return true if wanted.empty?

    primary = wanted.split("-").first
    accepted = [primary, MACRO_ALIASES[primary]].compact
    codes.any? { |known| known == wanted || accepted.include?(known.split("-").first) }
  end
end
