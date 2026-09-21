# frozen_string_literal: true

module MermaidTerm::Diagrams
  # Mermaid XY chart with vertical bars and braille line traces.
  module XYChart
    Diagram = Data.define(:title, :labels, :minimum, :maximum, :bars, :lines, :horizontal)
    def self.diagram_type = :xychart
    def self.keywords = %w[xychart-beta xychart]

    def self.parse(source)
      title = source.title
      labels = []
      minimum = 0.0
      maximum = nil
      bars = []
      lines = []
      findings = []
      horizontal = source.lines.first.to_s.include?("horizontal")
      source.lines.drop(1).each_with_index do |line, index|
        case line.strip
        when /\Atitle\s+["']?(.+?)["']?\z/
          title = Regexp.last_match(1)
        when /\Ax-axis\s+\[(.*)\]/
          labels = Regexp.last_match(1).split(",").map { |item| item.strip.delete_prefix('"').delete_suffix('"') }
        when /\Ay-axis\s+.*?(-?\d+(?:\.\d+)?)\s*-->\s*(-?\d+(?:\.\d+)?)\z/
          minimum = Regexp.last_match(1).to_f
          maximum = Regexp.last_match(2).to_f
        when /\A(bar|line)\s+\[([^\]]*)\]/
          kind = Regexp.last_match(1)
          values = Regexp.last_match(2).split(",").map { |value| Float(value.strip, exception: false) }
          if values.any?(&:nil?)
            findings << MermaidTerm::Diagrams.finding("invalid chart value", source, index + 1)
          else
            (kind == "bar" ? bars : lines) << values
          end
        when ""
          next
        else
          findings << MermaidTerm::Diagrams.finding("unrecognized xychart statement", source, index + 1)
        end
      end
      [Diagram.new(title: title, labels: labels.freeze, minimum: minimum, maximum: maximum,
                   bars: bars.freeze, lines: lines.freeze, horizontal: horizontal), findings]
    end

    def self.layout(ast, charset: :unicode, **)
      builder = Builder.new
      all = ast.bars.flatten + ast.lines.flatten
      count = [ast.labels.length, ast.bars.map(&:length).max.to_i, ast.lines.map(&:length).max.to_i].max
      return builder.scene if count.zero?
      return layout_horizontal(ast, charset, count, all) if ast.horizontal

      minimum = ast.minimum
      maximum = ast.maximum || [all.max.to_f, 1].max
      maximum = minimum + 1 if maximum <= minimum
      title_offset = ast.title ? 2 : 0
      builder.text(0, 0, ast.title, role: :emphasis) if ast.title
      plot_left = 7
      plot_top = title_offset
      plot_height = 10
      step = [4, ast.bars.length * 2 + 2].max
      plot_width = count * step
      6.times do |tick|
        value = maximum - (maximum - minimum) * tick / 5.0
        y = plot_top + tick * 2
        builder.text(0, y, Text.pad(format("%5g", value), 5, align: :right), role: :axis_label)
      end
      builder.line([[plot_left - 1, plot_top], [plot_left - 1, plot_top + plot_height],
                    [plot_left + plot_width, plot_top + plot_height]], role: :axis)
      ast.bars.each_with_index do |series, series_index|
        series.each_with_index do |value, index|
          rows = ((value - minimum) / (maximum - minimum) * plot_height * 8).clamp(0, plot_height * 8).round
          full, partial = rows.divmod(8)
          x = plot_left + index * step + series_index * 2
          full.times { |offset| builder.glyph(x, plot_top + plot_height - 1 - offset, charset == :ascii ? "#" : "█", role: :series_1) }
          if partial.positive? && full < plot_height
            char = charset == :ascii ? "#" : %w[▁ ▂ ▃ ▄ ▅ ▆ ▇][partial - 1]
            builder.glyph(x, plot_top + plot_height - 1 - full, char, role: :series_1)
          end
        end
      end
      ast.lines.each_with_index do |series, series_index|
        draw_line(builder, series, plot_left, plot_top, plot_height, step, minimum, maximum, charset, series_index)
      end
      count.times do |index|
        label = ast.labels[index] || index.to_s
        builder.text(plot_left + index * step, plot_top + plot_height + 1, label, role: :axis_label)
      end
      builder.scene
    end

    def self.layout_horizontal(ast, charset, count, all)
      builder = Builder.new
      y = 0
      if ast.title
        builder.text(0, y, ast.title, role: :emphasis)
        y += 2
      end
      labels = count.times.map { |index| ast.labels[index] || index.to_s }
      width = labels.map { |label| Text.width(label) }.max
      maximum = ast.maximum || [all.max.to_f, 1].max
      minimum = ast.minimum
      maximum = minimum + 1 if maximum <= minimum
      count.times do |index|
        label = labels[index]
        builder.text(0, y, Text.pad(label, width), role: :axis_label)
        ast.bars.each do |series|
          value = series[index].to_f
          length = ((value - minimum) / (maximum - minimum) * 40).clamp(0, 40).round
          builder.text(width + 2, y, (charset == :ascii ? "#" : "█") * length, role: :series_1)
          builder.text(width + 43, y, format("%g", value), role: :axis_label)
          y += 1
        end
        ast.lines.each do |series|
          value = series[index].to_f
          length = ((value - minimum) / (maximum - minimum) * 40).clamp(0, 40).round
          builder.text(width + 2 + length, y, charset == :ascii ? "*" : "⠿", role: :series_2)
          builder.text(width + 43, y, format("%g", value), role: :axis_label)
          y += 1
        end
      end
      builder.scene
    end

    def self.draw_line(builder, values, left, top, height, step, minimum, maximum, charset, series_index)
      return if values.empty?

      points = values.each_with_index.map do |value, index|
        [index * step * 2 + step, ((maximum - value) / (maximum - minimum) * (height * 4 - 1)).clamp(0, height * 4 - 1).round]
      end
      if charset == :ascii
        points.each { |x, y| builder.glyph(left + x / 2, top + y / 4, "*", role: :series_1) }
        return
      end
      pixels = {}
      points.each_cons(2) do |(x1, y1), (x2, y2)|
        steps = [(x2 - x1).abs, (y2 - y1).abs, 1].max
        (0..steps).each do |step_index|
          x = (x1 + (x2 - x1) * step_index.to_f / steps).round
          y = (y1 + (y2 - y1) * step_index.to_f / steps).round
          bit = [[0, 1, 2, 6], [3, 4, 5, 7]][x % 2][y % 4]
          key = [x / 2, y / 4]
          pixels[key] = pixels.fetch(key, 0) | (1 << bit)
        end
      end
      pixels.each do |(x, y), bits|
        builder.glyph(left + x, top + y, (0x2800 + bits).chr(Encoding::UTF_8), role: :"series_#{series_index + 1}")
      end
    end
  end
end
