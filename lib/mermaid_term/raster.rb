# frozen_string_literal: true

module MermaidTerm
  # Converts Scene primitives to terminal cells.
  module Raster
    require_relative "raster/box_drawing_table"

    Cell = Struct.new(:char, :arms, :weights, :owners, :role, :background, :protected, :continuation, :weight, :pattern, :rounded, keyword_init: true)
    ARM = { n: 1, e: 2, s: 4, w: 8 }.freeze
    INDEX = { n: 0, e: 1, s: 2, w: 3 }.freeze
    WEIGHT = { light: 1, heavy: 2, double: 3 }.freeze
    OPPOSITE = { n: :s, e: :w, s: :n, w: :e }.freeze
    ROUNDED = { 3 => "╰", 6 => "╭", 9 => "╯", 12 => "╮" }.freeze

    # Mutable raster grid. Bounds errors signal a layout bug.
    class Grid
      attr_reader :width, :height, :rows

      def initialize(width, height, crossings: :plain)
        @width, @height = width, height
        @crossings = crossings
        @rows = Array.new(height) { Array.new(width) { Cell.new(char: " ", arms: 0, weights: [0, 0, 0, 0]) } }
      end

      def at(x, y)
        raise RangeError, "drawing outside Scene: #{x},#{y}" unless x.between?(0, width - 1) && y.between?(0, height - 1)

        rows[y][x]
      end

      def line(points, stroke, role, protect: false, rounded: false, owner: nil)
        points.each_cons(2) do |(x1, y1), (x2, y2)|
          raise ArgumentError, "diagonal line" unless x1 == x2 || y1 == y2

          dx = x2 <=> x1
          dy = y2 <=> y1
          x, y = x1, y1
          until x == x2 && y == y2
            nx, ny = x + dx, y + dy
            direction = dx.positive? ? :e : dx.negative? ? :w : dy.positive? ? :s : :n
            add_arm(x, y, direction, stroke, role, protect, rounded, owner)
            add_arm(nx, ny, OPPOSITE.fetch(direction), stroke, role, protect, rounded, owner)
            x, y = nx, ny
          end
        end
      end

      def add_arm(x, y, direction, stroke, role, protect, rounded, owner)
        cell = at(x, y)
        return if cell.continuation

        cell.arms |= ARM.fetch(direction)
        if owner
          cell.owners ||= {}
          (cell.owners[direction] ||= []) << owner
        end
        index = INDEX.fetch(direction)
        cell.weights[index] = [cell.weights[index], WEIGHT.fetch(stroke.weight)].max
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

      def fill(rect, background)
        rect.y.upto(rect.y + rect.height - 1) do |y|
          rect.x.upto(rect.x + rect.width - 1) { |x| at(x, y).background = background }
        end
      end

      def lines(charset: :unicode)
        rows.map do |row|
          row.filter_map do |cell|
            next if cell.continuation

            [character(cell, charset), cell.role, cell.background]
          end
        end
      end

      def character(cell, charset)
        return cell.char if cell.arms.zero? || cell.char != " " && cell.protected

        arms = cell.arms
        if @crossings == :bridge && arms == 15 && !cell.protected && cell.owners
          horizontal = (cell.owners[:e] || []) + (cell.owners[:w] || [])
          vertical = (cell.owners[:n] || []) + (cell.owners[:s] || [])
          return charset == :ascii ? "|" : "│" if (horizontal & vertical).empty?
        end
        if charset == :ascii
          return "+" unless [5, 10].include?(arms)
          return arms == 5 ? "|" : cell.weight == :heavy ? "=" : cell.pattern == :dotted ? "." : "-"
        end
        return ROUNDED[arms] if cell.rounded && cell.weight == :light && ROUNDED.key?(arms)
        return cell.weight == :heavy ? "┇" : "┆" if cell.pattern == :dotted && arms == 5
        return cell.weight == :heavy ? "┅" : "┄" if cell.pattern == :dotted && arms == 10

        key = cell.weights.join
        BOX_DRAWING[key] || BOX_DRAWING[key.tr("3", "1")] || BOX_DRAWING[key.tr("32", "11")]
      end
    end

    module_function

    def rasterize(scene, charset: :unicode, rounded: true, ambiguous_width: 1, crossings: :plain)
      grid = Grid.new(scene.width, scene.height, crossings: crossings)
      scene.items.sort_by { |item| Scene::LAYERS.fetch(item.layer, 3) }.each do |item|
        case item
        in Scene::Box
          r = item.rect
          grid.line([[r.x, r.y], [r.x + r.width - 1, r.y], [r.x + r.width - 1, r.y + r.height - 1],
                     [r.x, r.y + r.height - 1], [r.x, r.y]], item.stroke, item.role,
                    protect: true, rounded: rounded && item.corners == :rounded)
        in Scene::Polyline
          grid.line(item.points, item.stroke, item.role, owner: item.points.first)
        in Scene::Text
          x = item.x
          Text.each_cell(item.string, ambiguous_width: ambiguous_width) do |char, cells|
            if charset == :ascii && cells == 2
              grid.put(x, item.y, "?", item.role)
              grid.put(x + 1, item.y, "?", item.role)
            else
              grid.put(x, item.y, charset == :ascii ? ascii(char) : char, item.role, ambiguous_width: ambiguous_width)
            end
            x += cells
          end
        in Scene::Marker
          char = marker(item.kind, item.direction, charset)
          grid.put(item.x, item.y, char, item.role, protect: true)
        in Scene::Glyph
          grid.put(item.x, item.y, charset == :ascii ? ascii(item.char) : item.char, item.role, protect: true)
        in Scene::Fill
          grid.fill(item.rect, item.role.to_s.delete_prefix("bg:")) if item.role.to_s.start_with?("bg:")
        end
      end
      grid
    end

    def marker(kind, direction, charset)
      return { arrow: { n: "^", e: ">", s: "v", w: "<" }, circle: "o", cross: "x",
               triangle: "^", diamond: "*", open_diamond: "o" }.fetch(kind).then { |v| v.is_a?(Hash) ? v.fetch(direction) : v } if charset == :ascii

      { arrow: { n: "▲", e: "▶", s: "▼", w: "◀" }, circle: "○", cross: "×",
        triangle: "△", diamond: "◆", open_diamond: "◇" }.fetch(kind).then { |v| v.is_a?(Hash) ? v.fetch(direction) : v }
    end

    def ascii(char)
      char.ascii_only? && char.ord.between?(32, 126) ? char : "?"
    end
  end
end
