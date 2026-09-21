# frozen_string_literal: true

module MermaidTerm
  # Terminal display widths, measured in cells rather than code points.
  module Text
    require_relative "text/east_asian_width_table"

    module_function

    def in_ranges?(code, ranges)
      low = 0
      high = ranges.length - 1
      while low <= high
        mid = (low + high) / 2
        first, last = ranges[mid]
        return true if code >= first && code <= last

        code < first ? high = mid - 1 : low = mid + 1
      end
      false
    end

    def each_cell(string, ambiguous_width: 1)
      return enum_for(__method__, string, ambiguous_width: ambiguous_width) unless block_given?

      string.to_s.scrub.scan(/\X/).each do |cluster|
        code = cluster.ord
        width = if in_ranges?(code, ZERO)
                  0
                elsif in_ranges?(code, WIDE) || (ambiguous_width == 2 && in_ranges?(code, AMBIGUOUS))
                  2
                else
                  1
                end
        yield cluster, width
      end
    end

    def width(string, ambiguous_width: 1)
      each_cell(string, ambiguous_width: ambiguous_width).sum { |_, cells| cells }
    end

    def truncate(string, max_width, omission: "…", ambiguous_width: 1)
      return string if width(string, ambiguous_width: ambiguous_width) <= max_width

      remaining = [max_width - width(omission, ambiguous_width: ambiguous_width), 0].max
      result = +""
      each_cell(string, ambiguous_width: ambiguous_width) do |cluster, cells|
        break if cells > remaining

        result << cluster
        remaining -= cells
      end
      result + (max_width >= width(omission, ambiguous_width: ambiguous_width) ? omission : "")
    end

    def pad(string, target_width, align: :left, ambiguous_width: 1)
      spaces = [target_width - width(string, ambiguous_width: ambiguous_width), 0].max
      left = case align
             when :right then spaces
             when :center then spaces / 2
             else 0
             end
      (" " * left) + string + (" " * (spaces - left))
    end

    def wrap(string, max_width, ambiguous_width: 1)
      raise ArgumentError, "width must be positive" unless max_width.positive?

      string.to_s.split("\n", -1).flat_map do |line|
        result = []
        current = +""
        used = 0
        line.scan(/\S+|\s+/).each do |token|
          token_width = width(token, ambiguous_width: ambiguous_width)
          if token.match?(/\A\s+\z/)
            if used.positive? && used + token_width <= max_width
              current << token
              used += token_width
            end
            next
          end
          if used + token_width > max_width && used.positive?
            result << current.rstrip
            current = +""
            used = 0
          end
          if token_width <= max_width
            current << token
            used += token_width
          else
            each_cell(token, ambiguous_width: ambiguous_width) do |cluster, cells|
              if used + cells > max_width && used.positive?
                result << current.rstrip
                current = +""
                used = 0
              end
              current << cluster
              used += cells
            end
          end
        end
        result << current
        result
      end
    end
  end
end
