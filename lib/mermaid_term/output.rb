# frozen_string_literal: true

module MermaidTerm
  # Plain and ANSI terminal output.
  module Output
    THEMES = Ractor.make_shareable({
      default: { node_border: 39, node_text: 255, edge: 110, edge_label: 222, marker: 203, container_border: 103, container_title: 222 },
      mono: {},
      high_contrast: { node_border: 15, node_text: 15, edge: 15, edge_label: 11, marker: 9 },
      solarized: { node_border: 37, node_text: 230, edge: 66, edge_label: 136, marker: 160 }
    })

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

        colored ? ansi_line(cells, THEMES.fetch(theme.to_sym)) : cells.map(&:first).join
      end.drop_while(&:empty?).reverse.drop_while(&:empty?).reverse.join("\n")
    end

    def ansi_line(cells, theme)
      current = nil
      result = +""
      cells.each do |char, role|
        next_style = theme[role]
        if next_style != current
          result << "\e[0m" if current
          result << "\e[38;5;#{next_style}m" if next_style
          current = next_style
        end
        result << char
      end
      result << "\e[0m" if current
      result
    end
  end
end
