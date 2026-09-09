# A sentence with the whitespace it was found in, so rendering never needs a second string to restore it.
class TranslationDiff::Segment
  attr_reader :source, :core
  attr_accessor :translation

  def initialize(source)
    @source = source
    @leading, @core, @trailing = source.partition(/\S.*\S|\S/m)
  end

  def translated? = !translation.nil?

  def empty? = core.empty?

  def render = "#{@leading}#{translated? ? translation : core}#{@trailing}"
end
