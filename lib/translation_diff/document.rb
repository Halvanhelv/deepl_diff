# A caller's value together with its Hash/Array shape, walked without ever flattening it into an array.
class TranslationDiff::Document
  def initialize(value) = @value = value

  # Returns a new structure of the same shape with every leaf String replaced by the block's result.
  def map(&) = walk(@value, &)

  # Returns the leaf strings in document order, without touching the original value.
  def strings
    [].tap { |acc| walk(@value) { |string| acc << string } }
  end

  private

  def walk(node, &block)
    case node
    when Hash then node.to_h { |key, value| [key, walk(value, &block)] }
    when Array then node.map { |value| walk(value, &block) }
    when String then block.call(node)
    else node
    end
  end
end
