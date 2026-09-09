# A sentence with the whitespace it was found in, so rendering never needs a second string to restore it.
class TranslationDiff::Segment
  attr_reader :source, :core
  attr_accessor :translation

  def initialize(source)
    @source = source.dup
    @leading, @core, @trailing = @source.partition(/[^[:space:]].*[^[:space:]]|[^[:space:]]/m)
  end

  # Reflects whether a translation is set right now, not history -- clearing it to nil flips this back to false.
  def translated? = !translation.nil?

  def empty? = core.empty?

  def render = "#{@leading}#{translated? ? translation : core}#{@trailing}"
end
