# frozen_string_literal: true

class DeepLDiff::Linearizer
  class << self
    def linearize(struct, array = [])
      case struct
      when Hash
        struct.each { |_k, v| linearize(v, array) }
      when Array
        struct.each { |v| linearize(v, array) }
      else
        array << struct
      end

      array
    end

    def restore(struct, array)
      case struct
      when Hash
        struct.transform_values { |v| restore(v, array) }
      when Array
        struct.map { |v| restore(v, array) }
      else
        array.shift
      end
    end
  end
end
