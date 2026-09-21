# frozen_string_literal: true

module MermaidTerm
  # Plain and ANSI terminal output.
  module Output
    THEMES = Shareable.make({
      default: { node_border: 39, node_text: 255, edge: 110, edge_label: 222, marker: 203,
                 container_border: 103, container_title: 222, axis: 244, axis_label: 250,
                 series_1: 39, series_2: 203, emphasis: 229, muted: 244 },
      mono: {},
      high_contrast: { node_border: 15, node_text: 15, edge: 15, edge_label: 11, marker: 9,
                       axis: 15, axis_label: 15, series_1: 11, series_2: 13, emphasis: 15 },
      solarized: { node_border: 37, node_text: 230, edge: 66, edge_label: 136, marker: 160,
                   axis: 244, axis_label: 187, series_1: 37, series_2: 166, emphasis: 230 }
    })
    BASIC = Shareable.make([[0, 0, 0], [128, 0, 0], [0, 128, 0], [128, 128, 0],
                                    [0, 0, 128], [128, 0, 128], [0, 128, 128], [192, 192, 192],
                                    [128, 128, 128], [255, 0, 0], [0, 255, 0], [255, 255, 0],
                                    [0, 0, 255], [255, 0, 255], [0, 255, 255], [255, 255, 255]])

    module_function

    def render(grid, charset: :unicode, color: false, theme: :default)
      raise ArgumentError, "unknown theme: #{theme}" unless THEMES.key?(theme.to_sym)

      colored = color == true || color == :always || (color == :auto && $stdout.tty?)
      colored = false if ENV.key?("NO_COLOR") && !ENV.key?("FORCE_COLOR")
      colored = true if ENV.key?("FORCE_COLOR") && color != false && color != :never
      grid.lines(charset: charset).map do |cells|
        last = cells.rindex { |char, _| char != " " }
        cells = last ? cells.take(last + 1) : []
        next "" if cells.empty?

        colored ? ansi_line(cells, THEMES.fetch(theme.to_sym), color_depth) : cells.map(&:first).join
      end.drop_while(&:empty?).reverse.drop_while(&:empty?).reverse.join("\n")
    end

    def ansi_line(cells, theme, depth)
      current = nil
      result = +""
      cells.each do |char, role, background|
        next_style = [role.to_s.start_with?("fg:") ? role.to_s.delete_prefix("fg:") : theme[role], background]
        if next_style != current
          result << "\e[0m" if current&.any?
          codes = []
          codes << color_code(next_style[0], depth) if next_style[0]
          codes << color_code(next_style[1], depth, foreground: false) if next_style[1]
          result << "\e[#{codes.join(';')}m" unless codes.empty?
          current = next_style
        end
        result << char
      end
      result << "\e[0m" if current&.any?
      result
    end

    def color_depth
      return :truecolor if %w[truecolor 24bit].include?(ENV["COLORTERM"])
      return :color256 if ENV["TERM"].to_s.include?("256color")

      :color16
    end

    def color_code(value, depth, foreground: true)
      prefix = foreground ? 38 : 48
      rgb = value.is_a?(Integer) ? rgb256(value) : hex_rgb(value)
      return "#{prefix};2;#{rgb.join(';')}" if depth == :truecolor
      if depth == :color256
        index = value.is_a?(Integer) ? value : (16..255).min_by { |candidate| rgb256(candidate).zip(rgb).sum { |a, b| (a - b)**2 } }
        return "#{prefix};5;#{index}"
      end

      nearest = BASIC.each_with_index.min_by { |candidate, _| candidate.zip(rgb).sum { |a, b| (a - b)**2 } }.last
      (nearest < 8 ? (foreground ? 30 : 40) + nearest : (foreground ? 90 : 100) + nearest - 8).to_s
    end

    def hex_rgb(value)
      hex = value.to_s.delete_prefix("#")
      hex = hex.chars.map { |char| char * 2 }.join if hex.length == 3
      [0, 2, 4].map { |offset| hex[offset, 2].to_i(16) }
    end

    def rgb256(index)
      return BASIC[index] if index < 16
      return Array.new(3, 8 + (index - 232) * 10) if index >= 232

      cube = index - 16
      [cube / 36, cube / 6 % 6, cube % 6].map { |value| value.zero? ? 0 : 55 + value * 40 }
    end
  end
end
