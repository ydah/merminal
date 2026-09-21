# frozen_string_literal: true

module MermaidTerm
  module Diagrams
    Text = MermaidTerm::Text
    Scene = MermaidTerm::Scene
    Flowchart = MermaidTerm::Flowchart

    # Shared Scene assembly for diagram plugins.
    class Builder
      def initialize
        @items = []
        @width = 0
        @height = 0
      end

      def text(x, y, string, role: :node_text)
        string.to_s.split("\n", -1).each_with_index do |line, offset|
          @items << Scene::Text.new(x: x, y: y + offset, string: line, role: role, layer: :label, emphasis: nil)
          reach(x + Text.width(line), y + offset + 1)
        end
      end

      def box(x, y, width, height, role: :node_border, rounded: false)
        @items << Scene::Box.new(rect: Scene::Rect.new(x: x, y: y, width: width, height: height),
                                 stroke: Scene::LIGHT, corners: rounded ? :rounded : :sharp, role: role,
                                 layer: role == :container_border ? :container : :node)
        reach(x + width, y + height)
      end

      def line(points, role: :edge, weight: :light, pattern: :solid)
        @items << Scene::Polyline.new(points: points, stroke: Scene::Stroke.new(weight: weight, pattern: pattern),
                                      role: role, layer: :edge)
        points.each { |x, y| reach(x + 1, y + 1) }
      end

      def marker(x, y, kind: :arrow, direction: :e)
        @items << Scene::Marker.new(x: x, y: y, kind: kind, direction: direction, role: :marker, layer: :marker)
        reach(x + 1, y + 1)
      end

      def glyph(x, y, char, role: :series_1)
        @items << Scene::Glyph.new(x: x, y: y, char: char, role: role, layer: :marker)
        reach(x + 1, y + 1)
      end

      def scene
        Scene.new(width: @width, height: @height, items: @items.freeze)
      end

      private

      def reach(x, y)
        @width = [@width, x].max
        @height = [@height, y].max
      end
    end

    module_function

    def finding(message, source, index, severity: :error)
      Diagnostic.new(severity: severity, message: message, line: source.line_map[index] || 1, column: 1, length: 1)
    end
  end
end
