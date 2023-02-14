# frozen_string_literal: true

# Adds same count leading-trailing spaces left has to the right
class DeepLDiff::Spacing
  class << self
    # DeepLDiff::Spacing.restore("  a ", "Z") # => "   Z "
    def restore(left, right)
      leading(left) + right.strip + trailing(left)
    end

    private

    def spaces(count)
      ([" "] * count).join
    end

    def leading(value)
      pos = value =~ /[^[:space:]]+/ui
      return "" if pos.nil? || pos.zero?

      value[0..(pos - 1)]
    end

    def trailing(value)
      pos = value =~ /[[:space:]]+\z/ui
      return "" if pos.nil?

      value[pos..]
    end
  end
end
