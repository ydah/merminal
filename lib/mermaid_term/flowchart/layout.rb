# frozen_string_literal: true

module MermaidTerm::Flowchart
  Scene = MermaidTerm::Scene
  Text = MermaidTerm::Text

  # Deterministic layered placement with channel routing.
  class Layout
    def initialize(ast, **options)
      @ast = ast
      @options = options
      @horizontal = %i[LR RL].include?(options.fetch(:direction, ast.direction))
      @reverse = %i[BT RL].include?(options.fetch(:direction, ast.direction))
      @node_gap = options.fetch(:node_gap, 3)
      @rank_gap = options.fetch(:rank_gap, 3)
      @padding = options.fetch(:node_padding_x, 2)
      @max_label_width = options.fetch(:max_label_width, 24)
      @ambiguous_width = options.fetch(:ambiguous_width, 1)
      @items = []
    end

    def scene
      return Scene.new(width: 0, height: 0, items: [].freeze) if @ast.nodes.empty?

      orient_edges
      assign_ranks
      order_nodes
      place_nodes
      draw_nodes
      draw_edges
      add_subgraphs
      flip_items if @reverse
      Scene.new(width: @width, height: @height, items: @items.freeze)
    end

    private

    def orient_edges
      outgoing = @ast.nodes.to_h { |node| [node.id, []] }
      @ast.edges.each { |edge| outgoing[edge.from] << edge if outgoing.key?(edge.from) }
      state = {}
      reversed = {}
      visit = lambda do |id|
        state[id] = :visiting
        outgoing.fetch(id, []).each do |edge|
          reversed[edge.id] = true if state[edge.to] == :visiting
          visit.call(edge.to) unless state[edge.to] || !outgoing.key?(edge.to)
        end
        state[id] = :done
      end
      @ast.nodes.each { |node| visit.call(node.id) unless state[node.id] }
      @oriented = @ast.edges.map { |edge| [edge, reversed[edge.id] ? edge.to : edge.from, reversed[edge.id] ? edge.from : edge.to, reversed.key?(edge.id)] }
    end

    def assign_ranks
      @ranks = @ast.nodes.to_h { |node| [node.id, 0] }
      indegree = @ranks.transform_values { 0 }
      @oriented.each { |_, from, to, _| indegree[to] += 1 unless from == to }
      queue = @ast.nodes.map(&:id).select { |id| indegree[id].zero? }
      until queue.empty?
        id = queue.shift
        @oriented.each do |edge, from, to, _|
          next unless from == id && to != id

          @ranks[to] = [@ranks[to], @ranks[id] + [edge.minlen, edge.label ? 2 : 1].max].max
          indegree[to] -= 1
          queue << to if indegree[to].zero?
        end
      end
      # A malformed cycle can survive DFS when parallel edges are involved.
      @ranks.keys.each { |id| @ranks[id] = 0 if indegree[id].positive? }
    end

    def order_nodes
      @groups = @ast.nodes.group_by { |node| @ranks[node.id] }
      4.times do
        [@groups.keys.sort, @groups.keys.sort.reverse].each do |ranks|
          ranks.each do |rank|
            neighbors = @groups[rank].to_h do |node|
              ids = @oriented.filter_map do |_, from, to, _|
                from == node.id ? to : to == node.id ? from : nil
              end
              positions = ids.filter_map { |id| @groups[@ranks[id]]&.index { |peer| peer.id == id } }
              [node.id, positions.empty? ? nil : positions.sort[positions.length / 2]]
            end
            @groups[rank] = @groups[rank].each_with_index.sort_by { |node, index| [neighbors[node.id] || index, index] }.map(&:first)
          end
        end
      end
    end

    def place_nodes
      @labels = @ast.nodes.to_h do |node|
        [node.id, MermaidTerm::Text.wrap(node.label, @max_label_width, ambiguous_width: @ambiguous_width)]
      end
      @sizes = @ast.nodes.to_h do |node|
        width = @labels[node.id].map { |line| MermaidTerm::Text.width(line, ambiguous_width: @ambiguous_width) }.max.to_i + @padding * 2 + 2
        width += 2 if %i[circle double_circle decision hexagon].include?(node.shape)
        [node.id, [width, @labels[node.id].length + 2]]
      end
      @positions = {}
      ranks = @groups.keys.sort
      cursor = 1
      ranks.each do |rank|
        channel_edges = @oriented.count { |_, from, to, _| @ranks[from] == rank - 1 && @ranks[to] == rank }
        extra = @horizontal ? @oriented.filter_map { |edge, from, to, _| Text.width(edge.label.to_s) if @ranks[from] == rank - 1 && @ranks[to] == rank }.max.to_i : channel_edges * 2
        cursor += [@rank_gap, extra + 2].max if rank.positive?
        order = 1
        @groups[rank].each do |node|
          width, height = @sizes.fetch(node.id)
          @positions[node.id] = @horizontal ? [cursor, order] : [order, cursor]
          order += (@horizontal ? height : width) + @node_gap
        end
        cursor += @groups[rank].map { |node| @horizontal ? @sizes[node.id][0] : @sizes[node.id][1] }.max.to_i
      end
      @width = @positions.map { |id, (x, _)| x + @sizes[id][0] }.max + 2
      @height = @positions.map { |id, (_, y)| y + @sizes[id][1] }.max + 2
      @outer_track = @horizontal ? @height + 2 : @width + 2
      long_edges = @oriented.count { |_, from, to, _| (@ranks[to] - @ranks[from]).abs != 1 }
      @horizontal ? @height += long_edges * 2 + 5 : @width += long_edges * 2 + 5
    end

    def draw_nodes
      @ast.nodes.each do |node|
        x, y = @positions.fetch(node.id)
        w, h = @sizes.fetch(node.id)
        corners = %i[rounded stadium circle double_circle].include?(node.shape) ? :rounded : :sharp
        @items << Scene::Box.new(rect: Scene::Rect.new(x: x, y: y, width: w, height: h), stroke: Scene::LIGHT,
                                 corners: corners, role: :node_border, layer: :node)
        @labels[node.id].each_with_index do |line, index|
          offset = (w - Text.width(line, ambiguous_width: @ambiguous_width)) / 2
          @items << Scene::Text.new(x: x + offset, y: y + 1 + index, string: line, role: :node_text,
                                    layer: :label, emphasis: nil)
        end
        decorate(node, x, y, w, h)
      end
    end

    def decorate(node, x, y, w, h)
      case node.shape
      when :decision, :hexagon
        @items << Scene::Glyph.new(x: x, y: y + h / 2, char: "<", role: :node_border, layer: :marker)
        @items << Scene::Glyph.new(x: x + w - 1, y: y + h / 2, char: ">", role: :node_border, layer: :marker)
      when :stadium
        @items << Scene::Glyph.new(x: x, y: y + h / 2, char: "(", role: :node_border, layer: :marker)
        @items << Scene::Glyph.new(x: x + w - 1, y: y + h / 2, char: ")", role: :node_border, layer: :marker)
      when :subroutine
        @items << Scene::Polyline.new(points: [[x + 2, y], [x + 2, y + h - 1]], stroke: Scene::LIGHT, role: :node_border, layer: :node)
        @items << Scene::Polyline.new(points: [[x + w - 3, y], [x + w - 3, y + h - 1]], stroke: Scene::LIGHT, role: :node_border, layer: :node)
      when :database
        @items << Scene::Polyline.new(points: [[x, y + 1], [x + w - 1, y + 1]], stroke: Scene::LIGHT, role: :node_border, layer: :node)
      end
    end

    def draw_edges
      tracks = Hash.new(0)
      outer = 0
      @oriented.each do |edge, from, to, reversed|
        next if edge.stroke == :invisible

        if from == to || @ranks[to] - @ranks[from] != 1
          points = outer_route(from, to, outer)
          outer += 1
        else
          rank = @ranks[from]
          points = channel_route(from, to, tracks[rank])
          tracks[rank] += 1
        end
        stroke = Scene::Stroke.new(weight: edge.stroke == :heavy ? :heavy : :light,
                                   pattern: edge.stroke == :dotted ? :dotted : :solid)
        @items << Scene::Polyline.new(points: points, stroke: stroke, role: :edge, layer: :edge)
        marker_endpoint(edge, points, reversed)
        label_edge(edge, points) if edge.label && !edge.label.empty?
      end
    end

    def port(id, end_port: false)
      x, y = @positions.fetch(id)
      w, h = @sizes.fetch(id)
      @horizontal ? [end_port ? x : x + w - 1, y + h / 2] : [x + w / 2, end_port ? y : y + h - 1]
    end

    def channel_route(from, to, track)
      a = port(from)
      b = port(to, end_port: true)
      if @horizontal
        middle = a[0] + 2 + track * 2
        [a, [middle, a[1]], [middle, b[1]], b]
      else
        middle = a[1] + 2 + track * 2
        [a, [a[0], middle], [b[0], middle], b]
      end
    end

    def outer_route(from, to, index)
      a = port(from)
      b = port(to, end_port: true)
      track = @outer_track + index * 2
      if @horizontal
        [a, [a[0] + 2, a[1]], [a[0] + 2, track], [b[0] - 2, track], [b[0] - 2, b[1]], b]
      else
        [a, [a[0], a[1] + 2], [track, a[1] + 2], [track, b[1] - 2], [b[0], b[1] - 2], b]
      end
    end

    def marker_endpoint(edge, points, reversed)
      kind = reversed ? edge.end_marker : edge.end_marker
      return unless kind

      tip = reversed ? points.first : points.last
      neighbor = reversed ? points[1] : points[-2]
      direction = if @horizontal
                    reversed ? :w : :e
                  else
                    reversed ? :n : :s
                  end
      x = tip[0] + (direction == :e ? -1 : direction == :w ? 1 : 0)
      y = tip[1] + (direction == :s ? -1 : direction == :n ? 1 : 0)
      @items << Scene::Marker.new(x: x, y: y, kind: kind, direction: direction, role: :marker, layer: :marker)
      return unless edge.start_marker

      @items << Scene::Marker.new(x: neighbor[0], y: neighbor[1], kind: edge.start_marker,
                                  direction: direction == :e ? :w : direction == :s ? :n : :e,
                                  role: :marker, layer: :marker)
    end

    def label_edge(edge, points)
      text = edge.label.to_s
      a, b = points[0], points[-1]
      x, y = if @horizontal
               [a[0] + 1, [a[1], b[1]].min - 1]
             else
               [[a[0], b[0]].min, [a[1], b[1]].min + 1]
             end
      x = [[x, 0].max, @width - Text.width(text, ambiguous_width: @ambiguous_width)].min
      y = [[y, 0].max, @height - 1].min
      @items << Scene::Text.new(x: x, y: y, string: text, role: :edge_label, layer: :label, emphasis: nil)
    end

    def add_subgraphs
      @ast.subgraphs.each do |group|
        members = group.node_ids.uniq.filter_map { |id| @positions[id] && [@positions[id], @sizes[id]] }
        next if members.empty?

        left = [members.map { |(x, _), _| x }.min - 1, 0].max
        top = [members.map { |(_, y), _| y }.min - 2, 0].max
        right = members.map { |(x, _), (w, _)| x + w }.max
        bottom = members.map { |(_, y), (_, h)| y + h }.max
        next if left.negative? || top.negative? || right >= @width || bottom >= @height

        @items << Scene::Box.new(rect: Scene::Rect.new(x: left, y: top, width: right - left + 1, height: bottom - top + 1),
                                 stroke: Scene::LIGHT, corners: :sharp, role: :container_border, layer: :container)
        @items << Scene::Text.new(x: left + 2, y: top, string: group.label, role: :container_title,
                                  layer: :label, emphasis: nil)
      end
    end

    def flip_items
      @items.map! do |item|
        case item
        in Scene::Box
          r = item.rect
          item.with(rect: Scene::Rect.new(x: @horizontal ? @width - r.x - r.width : r.x,
                                           y: @horizontal ? r.y : @height - r.y - r.height, width: r.width, height: r.height))
        in Scene::Polyline
          item.with(points: item.points.map { |x, y| [@horizontal ? @width - 1 - x : x, @horizontal ? y : @height - 1 - y] })
        in Scene::Text
          item.with(x: @horizontal ? @width - item.x - Text.width(item.string, ambiguous_width: @ambiguous_width) : item.x,
                    y: @horizontal ? item.y : @height - 1 - item.y)
        in Scene::Marker
          item.with(x: @horizontal ? @width - 1 - item.x : item.x, y: @horizontal ? item.y : @height - 1 - item.y,
                    direction: { e: :w, w: :e, n: :s, s: :n }.fetch(item.direction))
        in Scene::Glyph
          item.with(x: @horizontal ? @width - 1 - item.x : item.x, y: @horizontal ? item.y : @height - 1 - item.y)
        else item
        end
      end
    end
  end
end
