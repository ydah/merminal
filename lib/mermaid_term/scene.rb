# frozen_string_literal: true

module MermaidTerm
  # Immutable drawing instructions in terminal cell coordinates.
  Scene = Data.define(:width, :height, :items)
  class Scene
    Rect = Data.define(:x, :y, :width, :height)
    Stroke = Data.define(:weight, :pattern)
    Box = Data.define(:rect, :stroke, :corners, :role, :layer)
    Polyline = Data.define(:points, :stroke, :role, :layer) do
      def initialize(points:, **options)
        raise ArgumentError, "polyline must be orthogonal" unless points.each_cons(2).all? { |a, b| a[0] == b[0] || a[1] == b[1] }

        super
      end
    end
    Text = Data.define(:x, :y, :string, :role, :layer, :emphasis)
    Marker = Data.define(:x, :y, :kind, :direction, :role, :layer)
    Glyph = Data.define(:x, :y, :char, :role, :layer)
    Fill = Data.define(:rect, :role, :layer)

    LIGHT = Stroke.new(weight: :light, pattern: :solid)
    LAYERS = { background: 0, container: 1, edge: 2, node: 3, marker: 4, label: 5 }.freeze
  end
end
