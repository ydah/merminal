# frozen_string_literal: true

module MermaidTerm::Diagrams
  # Mermaid pie data as proportional horizontal bars.
  module Pie
    Diagram = Data.define(:title, :show_data, :entries)
    def self.diagram_type = :pie
    def self.keywords = %w[pie]

    def self.parse(source)
      title = source.title
      show_data = source.lines.first.to_s.include?("showData")
      entries = []
      findings = []
      source.lines.drop(1).each_with_index do |line, index|
        case line.strip
        when /\Atitle\s+(.+)\z/i
          title = Regexp.last_match(1)
        when /\AshowData\z/i
          show_data = true
        when /\A["'](.+?)["']\s*:\s*(-?\d+(?:\.\d+)?)\z/
          value = Regexp.last_match(2).to_f
          if value.negative?
            findings << MermaidTerm::Diagrams.finding("pie values must be nonnegative", source, index + 1)
          else
            entries << [Regexp.last_match(1), value]
          end
        when ""
          next
        else
          findings << MermaidTerm::Diagrams.finding("unrecognized pie statement", source, index + 1)
        end
      end
      [Diagram.new(title: title, show_data: show_data, entries: entries.freeze), findings]
    end

    def self.layout(ast, charset: :unicode, **)
      builder = Builder.new
      y = 0
      if ast.title
        builder.text(0, y, ast.title, role: :emphasis)
        y += 2
      end
      total = ast.entries.sum(&:last)
      label_width = ast.entries.map { |label, _| Text.width(label) }.max.to_i
      ast.entries.each do |label, value|
        fraction = total.zero? ? 0 : value / total
        eighths = (fraction * 30 * 8).round
        bar = if charset == :ascii
                "#" * (eighths / 8) + (eighths % 8 > 0 ? "+" : "")
              else
                "█" * (eighths / 8) + (eighths % 8 > 0 ? %w[▏ ▎ ▍ ▌ ▋ ▊ ▉][eighths % 8 - 1] : "")
              end
        builder.text(0, y, Text.pad(label, label_width))
        builder.text(label_width + 2, y, bar, role: :series_1)
        suffix = format("%5.1f%%", fraction * 100)
        suffix += " (#{format('%g', value)})" if ast.show_data
        builder.text(label_width + 34, y, suffix, role: :axis_label)
        y += 1
      end
      builder.scene
    end
  end
end
