# frozen_string_literal: true

module MermaidTerm
  # Converts Scene primitives to terminal cells.
  module Raster
    Cell = Struct.new(:char, :arms, :role, :protected, :continuation, :weight, :pattern, :rounded, keyword_init: true)
    ARM = { n: 1, e: 2, s: 4, w: 8 }.freeze
    OPPOSITE = { n: :s, e: :w, s: :n, w: :e }.freeze
    LIGHT = {
      1 => "╵", 2 => "╶", 3 => "└", 4 => "╷", 5 => "│", 6 => "┌", 7 => "├",
      8 => "╴", 9 => "┘", 10 => "─", 11 => "┴", 12 => "┐", 13 => "┤", 14 => "┬", 15 => "┼"
    }.freeze
    HEAVY = { 5 => "┃", 10 => "━", 15 => "╋" }.freeze
    DOUBLE = { 5 => "║", 10 => "═", 15 => "╬" }.freeze
    ROUNDED = { 3 => "╰", 6 => "╭", 9 => "╯", 12 => "╮" }.freeze

    # Mutable raster grid. Bounds errors signal a layout bug.
    class Grid
      attr_reader :width, :height, :rows

      def initialize(width, height)
        @width, @height = width, height
        @rows = Array.new(height) { Array.new(width) { Cell.new(char: " ", arms: 0) } }
      end

      def at(x, y)
        raise RangeError, "drawing outside Scene: #{x},#{y}" unless x.between?(0, width - 1) && y.between?(0, height - 1)

        rows[y][x]
      end

      def line(points, stroke, role, protect: false, rounded: false)
        points.each_cons(2) do |(x1, y1), (x2, y2)|
          raise ArgumentError, "diagonal line" unless x1 == x2 || y1 == y2

          dx = x2 <=> x1
          dy = y2 <=> y1
          x, y = x1, y1
          until x == x2 && y == y2
            nx, ny = x + dx, y + dy
            direction = dx.positive? ? :e : dx.negative? ? :w : dy.positive? ? :s : :n
            add_arm(x, y, direction, stroke, role, protect, rounded)
            add_arm(nx, ny, OPPOSITE.fetch(direction), stroke, role, protect, rounded)
            x, y = nx, ny
          end
        end
      end

      def add_arm(x, y, direction, stroke, role, protect, rounded)
        cell = at(x, y)
        return if cell.continuation

        cell.arms |= ARM.fetch(direction)
        cell.role = role if !cell.protected || protect
        cell.protected ||= protect
        cell.weight = stroke.weight if !cell.weight || cell.weight == :light
        cell.pattern = stroke.pattern
        cell.rounded ||= rounded
      end

      def put(x, y, char, role, protect: false, ambiguous_width: 1)
        cells = Text.width(char, ambiguous_width: ambiguous_width)
        return if cells.zero?

        cell = at(x, y)
        raise RangeError, "drawing across Scene edge" if cells == 2 && x == width - 1
        return if cell.protected && !protect

        cell.char = char
        cell.arms = 0
        cell.role = role
        cell.protected ||= protect
        if cells == 2
          follower = at(x + 1, y)
          follower.char = ""
          follower.arms = 0
          follower.continuation = true
          follower.role = role
        end
      end

      def lines(charset: :unicode)
        rows.map do |row|
          row.filter_map do |cell|
            next if cell.continuation

            [character(cell, charset), cell.role]
          end
        end
      end

      def character(cell, charset)
        return cell.char if cell.arms.zero? || cell.char != " " && cell.protected

        arms = cell.arms
        if charset == :ascii
          return "+" unless [5, 10].include?(arms)
          return arms == 5 ? "|" : cell.weight == :heavy ? "=" : cell.pattern == :dotted ? "." : "-"
        end
        return ROUNDED[arms] if cell.rounded && cell.weight == :light && ROUNDED.key?(arms)
        return cell.weight == :heavy ? "┇" : "┆" if cell.pattern == :dotted && arms == 5
        return cell.weight == :heavy ? "┅" : "┄" if cell.pattern == :dotted && arms == 10

        table = { heavy: HEAVY, double: DOUBLE }[cell.weight]
        (table && table[arms]) || LIGHT.fetch(arms)
      end
    end

    module_function

    def rasterize(scene, charset: :unicode, rounded: true, ambiguous_width: 1)
      grid = Grid.new(scene.width, scene.height)
      scene.items.sort_by { |item| Scene::LAYERS.fetch(item.layer, 3) }.each do |item|
        case item
        in Scene::Box
          r = item.rect
          grid.line([[r.x, r.y], [r.x + r.width - 1, r.y], [r.x + r.width - 1, r.y + r.height - 1],
                     [r.x, r.y + r.height - 1], [r.x, r.y]], item.stroke, item.role,
                    protect: true, rounded: rounded && item.corners == :rounded)
        in Scene::Polyline
          grid.line(item.points, item.stroke, item.role)
        in Scene::Text
          x = item.x
          Text.each_cell(item.string, ambiguous_width: ambiguous_width) do |char, cells|
            grid.put(x, item.y, charset == :ascii ? ascii(char) : char, item.role, ambiguous_width: ambiguous_width)
            x += cells
          end
        in Scene::Marker
          char = marker(item.kind, item.direction, charset)
          grid.put(item.x, item.y, char, item.role, protect: true)
        in Scene::Glyph
          grid.put(item.x, item.y, charset == :ascii ? ascii(item.char) : item.char, item.role, protect: true)
        in Scene::Fill
          # Background color is applied by the ANSI output stage.
        end
      end
      grid
    end

    def marker(kind, direction, charset)
      return { arrow: { n: "^", e: ">", s: "v", w: "<" }, circle: "o", cross: "x" }.fetch(kind).then { |v| v.is_a?(Hash) ? v.fetch(direction) : v } if charset == :ascii

      { arrow: { n: "▲", e: "▶", s: "▼", w: "◀" }, circle: "○", cross: "×" }.fetch(kind).then { |v| v.is_a?(Hash) ? v.fetch(direction) : v }
    end

    def ascii(char)
      char.ascii_only? && char.ord.between?(32, 126) ? char : "?"
    end
  end
end
