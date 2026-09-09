# The two things this pipeline has always promised about a caller's structure that Document deliberately does not:
# a nested nil comes back as the empty string, and the size of a document is every leaf in it, translatable or not.
module TranslationDiff::Leaves
  # Document hands every non-String leaf straight back, which is the honest behaviour for a general structural map.
  # Answering a nested nil with "" is the pipeline's own promise, so it is made here rather than there.
  def self.collapse_nils(node)
    case node
    when Hash then node.to_h { |key, value| [key, collapse_nils(value)] }
    when Array then node.map { |value| collapse_nils(value) }
    when nil then ""
    else node
    end
  end

  # Every leaf the caller wrote, whatever its type: the number a `translate` payload reports as `values`.
  def self.count(node)
    return node.each_value.sum { |value| count(value) } if node.is_a?(Hash)
    return node.sum { |value| count(value) } if node.is_a?(Array)

    1
  end
end
