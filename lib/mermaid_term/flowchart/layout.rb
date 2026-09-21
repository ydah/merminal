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
      @max_group_depth = @ast.subgraphs.map { |group| group_depth(group) }.max.to_i
      @cluster_margin = @ast.subgraphs.empty? ? 0 : 2 * (@max_group_depth + 1)
      @node_gap = [@node_gap, @cluster_margin * 2 + 1].max if @cluster_margin.positive?
      @rank_gap = [@rank_gap, @cluster_margin * 2 + 1].max if @cluster_margin.positive?
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
      clip_group_edges
      draw_markers
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

          @ranks[to] = [@ranks[to], @ranks[id] + edge.minlen].max
          indegree[to] -= 1
          queue << to if indegree[to].zero?
        end
      end
      # A malformed cycle can survive DFS when parallel edges are involved.
      @ranks.keys.each { |id| @ranks[id] = 0 if indegree[id].positive? }
    end

    def order_nodes
      @groups = @ast.nodes.group_by { |node| @ranks[node.id] }
      # ponytail: source order keeps cluster members together; add block median sweeps if crossings become a problem.
      return if @ast.subgraphs.any?

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
        width += 2 if %i[circle double_circle decision hexagon subroutine].include?(node.shape)
        height = @labels[node.id].length + 2 + (node.shape == :database ? 1 : 0)
        width = [width, 9].max if %i[fork join].include?(node.shape)
        height = [height, 5].max if @horizontal && %i[fork join].include?(node.shape)
        incoming = @oriented.count { |_, from, to, _| to == node.id && from != to }
        @horizontal ? height = [height, incoming + 2].max : width = [width, incoming + 2].max
        [node.id, [width, height]]
      end
      @positions = {}
      ranks = @groups.keys.sort
      cursor = 3 + @cluster_margin
      ranks.each do |rank|
        order = 1 + @cluster_margin
        @groups[rank].each do |node|
          width, height = @sizes.fetch(node.id)
          @positions[node.id] = @horizontal ? [cursor, order] : [order, cursor]
          order += (@horizontal ? height : width) + @node_gap
        end
        cursor += @groups[rank].map { |node| @horizontal ? @sizes[node.id][0] : @sizes[node.id][1] }.max.to_i
      end
      @input_ports = {}
      @ast.nodes.each do |node|
        incoming = @oriented.select { |_, from, to, _| to == node.id && from != to }
        incoming.sort_by! { |edge, from, _, _| [@horizontal ? @positions[from][1] : @positions[from][0], edge.id] }
        dimension = @horizontal ? @sizes[node.id][1] : @sizes[node.id][0]
        @input_ports[node.id] = incoming.each_with_index.to_h do |(edge, _, _, _), index|
          [edge.id, ((dimension - 1) * (index + 1).to_f / (incoming.length + 1)).round]
        end
      end
      allocate_channel_tracks
      cursor = 3 + @cluster_margin
      ranks.each_with_index do |rank, index|
        if index.positive?
          previous = ranks[index - 1]
          label_width = @oriented.filter_map do |edge, from, to, _|
            Text.width(edge.label.to_s) if @ranks[from] == previous && @ranks[to] == rank
          end.max.to_i
          cursor += [@rank_gap, @track_count.fetch(previous, 0) * 2 + 2,
                     @horizontal ? label_width + 4 : 0].max
        end
        @groups[rank].each do |node|
          point = @positions.fetch(node.id)
          @positions[node.id] = @horizontal ? [cursor, point[1]] : [point[0], cursor]
        end
        cursor += @groups[rank].map { |node| @horizontal ? @sizes[node.id][0] : @sizes[node.id][1] }.max.to_i
      end
      @rank_ends = @groups.to_h do |rank, nodes|
        [rank, nodes.map { |node| @horizontal ? @positions[node.id][0] + @sizes[node.id][0] - 1 :
                                           @positions[node.id][1] + @sizes[node.id][1] - 1 }.max]
      end
      @width = @positions.map { |id, (x, _)| x + @sizes[id][0] }.max + 2
      @height = @positions.map { |id, (_, y)| y + @sizes[id][1] }.max + 2
      @width += @cluster_margin
      @height += @cluster_margin
      @outer_track = @horizontal ? @height + 2 : @width + 2
      @outer_offsets = {}
      outer_span = 0
      @oriented.each do |edge, from, to, _|
        next if @ranks[to] - @ranks[from] == 1 && from != to

        @outer_offsets[edge.id] = outer_span
        outer_span += @horizontal ? 2 : Text.width(edge.label.to_s, ambiguous_width: @ambiguous_width) + 2
      end
      if @horizontal
        @height += outer_span + 5
      else
        @width += outer_span + 5
      end
      @width += @ast.edges.map { |edge| Text.width(edge.label.to_s, ambiguous_width: @ambiguous_width) }.max.to_i + 2
    end

    def allocate_channel_tracks
      intervals = Hash.new { |hash, rank| hash[rank] = {} }
      @oriented.each do |edge, from, to, _|
        next unless from != to && @ranks[to] - @ranks[from] == 1

        rank = @ranks[from]
        a = port(from)
        b = port(to, end_port: true, edge_id: edge.id)
        left, right = [@horizontal ? a[1] : a[0], @horizontal ? b[1] : b[0]].minmax
        if !@horizontal && edge.label && !edge.label.empty?
          right = [right, right + 1 + Text.width(edge.label, ambiguous_width: @ambiguous_width)].max
        end
        key = edge.label && !edge.label.empty? ? [from, edge.id] : from
        group = intervals[rank][key] ||= { left: left, right: right, edges: [] }
        group[:left] = [group[:left], left].min
        group[:right] = [group[:right], right].max
        group[:edges] << edge.id
      end
      @track_for_edge = {}
      @track_count = {}
      intervals.each do |rank, groups|
        track_ends = []
        groups.values.sort_by { |group| [group[:left], group[:right]] }.each do |group|
          track = track_ends.index { |right| right + 1 < group[:left] } || track_ends.length
          track_ends[track] = group[:right]
          group[:edges].each { |id| @track_for_edge[id] = track }
        end
        @track_count[rank] = track_ends.length
      end
    end

    def draw_nodes
      @ast.nodes.each do |node|
        x, y = @positions.fetch(node.id)
        w, h = @sizes.fetch(node.id)
        if %i[fork join].include?(node.shape)
          points = @horizontal ? [[x + w / 2, y], [x + w / 2, y + h - 1]] : [[x, y + h / 2], [x + w - 1, y + h / 2]]
          @items << Scene::Polyline.new(points: points, stroke: Scene::Stroke.new(weight: :heavy, pattern: :solid),
                                        role: :node_border, layer: :node)
          next
        end
        corners = %i[rounded stadium circle double_circle].include?(node.shape) ? :rounded : :sharp
        style = @ast.styles[node.id] || node.classes.reverse.filter_map { |name| @ast.styles["class:#{name}"] }.first
        fill = css_color(style, "fill")
        border = css_color(style, "stroke")
        foreground = css_color(style, "color")
        rect = Scene::Rect.new(x: x, y: y, width: w, height: h)
        @items << Scene::Fill.new(rect: rect, role: :"bg:#{fill}", layer: :background) if fill
        @items << Scene::Box.new(rect: rect, stroke: Scene::LIGHT,
                                 corners: corners, role: border ? :"fg:#{border}" : :node_border, layer: :node)
        @labels[node.id].each_with_index do |line, index|
          offset = (w - Text.width(line, ambiguous_width: @ambiguous_width)) / 2
          start = [(h - @labels[node.id].length) / 2, node.shape == :database ? 2 : 1].max
          text_y = y + start + index
          @items << Scene::Text.new(x: x + offset, y: text_y, string: line, role: foreground ? :"fg:#{foreground}" : :node_text,
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
      when :double_circle
        @items << Scene::Glyph.new(x: x + 1, y: y + h / 2, char: "(", role: :node_border, layer: :marker)
        @items << Scene::Glyph.new(x: x + w - 2, y: y + h / 2, char: ")", role: :node_border, layer: :marker)
      when :parallelogram
        @items << Scene::Glyph.new(x: x, y: y + h / 2, char: "/", role: :node_border, layer: :marker)
        @items << Scene::Glyph.new(x: x + w - 1, y: y + h / 2, char: "/", role: :node_border, layer: :marker)
      when :trapezoid
        @items << Scene::Glyph.new(x: x, y: y + h / 2, char: "/", role: :node_border, layer: :marker)
        @items << Scene::Glyph.new(x: x + w - 1, y: y + h / 2, char: "\\", role: :node_border, layer: :marker)
      when :flag
        @items << Scene::Glyph.new(x: x, y: y + h / 2, char: ">", role: :node_border, layer: :marker)
      end
    end

    def draw_edges
      @edge_item_indices = {}
      @oriented.each do |edge, from, to, _reversed|
        next if edge.stroke == :invisible

        if from == to || @ranks[to] - @ranks[from] != 1
          points = outer_route(from, to, @outer_offsets.fetch(edge.id), edge.id)
        else
          points = channel_route(from, to, @track_for_edge.fetch(edge.id), edge.id)
        end
        stroke = Scene::Stroke.new(weight: edge.stroke == :heavy ? :heavy : :light,
                                   pattern: edge.stroke == :dotted ? :dotted : :solid)
        style = @ast.styles["link:#{edge.id}"] || @ast.styles["link:default"]
        color = css_color(style, "stroke")
        @edge_item_indices[edge.id] = @items.length
        @items << Scene::Polyline.new(points: points, stroke: stroke, role: color ? :"fg:#{color}" : :edge, layer: :edge)
        label_edge(edge, points) if edge.label && !edge.label.empty?
      end
    end

    def draw_markers
      @oriented.each do |edge, _, _, reversed|
        index = @edge_item_indices[edge.id]
        marker_endpoint(edge, @items[index].points, reversed) if index
      end
    end

    def port(id, end_port: false, edge_id: nil)
      x, y = @positions.fetch(id)
      w, h = @sizes.fetch(id)
      offset = end_port ? @input_ports.fetch(id, {})[edge_id] : nil
      node = @ast.nodes.find { |candidate| candidate.id == id }
      if node && %i[fork join].include?(node.shape)
        return @horizontal ? [x + w / 2, y + (offset || h / 2)] : [x + (offset || w / 2), y + h / 2]
      end
      @horizontal ? [end_port ? x : x + w - 1, y + (offset || h / 2)] : [x + (offset || w / 2), end_port ? y : y + h - 1]
    end

    def channel_route(from, to, track, edge_id)
      a = port(from)
      b = port(to, end_port: true, edge_id: edge_id)
      middle = @rank_ends.fetch(@ranks[from]) + 2 + track * 2
      if @horizontal
        [a, [middle, a[1]], [middle, b[1]], b]
      else
        [a, [a[0], middle], [b[0], middle], b]
      end
    end

    def outer_route(from, to, offset, edge_id)
      # ponytail: long and cyclic edges use outside lanes; add channel segments if dense graphs need tighter layouts.
      a = port(from)
      b = port(to, end_port: true, edge_id: edge_id)
      track = @outer_track + offset
      if @horizontal
        turn = @groups[@ranks[from]].map { |node| @positions[node.id][0] + @sizes[node.id][0] }.max + 1
        [a, [turn, a[1]], [turn, track], [b[0] - 2, track], [b[0] - 2, b[1]], b]
      else
        turn = @groups[@ranks[from]].map { |node| @positions[node.id][1] + @sizes[node.id][1] }.max + 1
        [a, [a[0], turn], [track, turn], [track, b[1] - 2], [b[0], b[1] - 2], b]
      end
    end

    def marker_endpoint(edge, points, reversed)
      forward = @horizontal ? :e : :s
      backward = @horizontal ? :w : :n
      put_marker(reversed ? points.first : points.last, edge.end_marker, reversed ? backward : forward)
      put_marker(reversed ? points.last : points.first, edge.start_marker, reversed ? forward : backward)
    end

    def put_marker(tip, kind, direction)
      return unless kind

      x = tip[0] + (direction == :e ? -1 : direction == :w ? 1 : 0)
      y = tip[1] + (direction == :s ? -1 : direction == :n ? 1 : 0)
      @items << Scene::Marker.new(x: x, y: y, kind: kind, direction: direction, role: :marker, layer: :marker)
    end

    def label_edge(edge, points)
      text = edge.label.to_s
      x, y = if points.length > 4
               @horizontal ? [points[1][0], points[2][1] - 1] : [points[2][0] + 1, points[1][1] - 1]
             elsif @horizontal
               [points[1][0], [points[0][1], points[-1][1]].min - 1]
             else
               [[points[0][0], points[-1][0]].max + 2, points[1][1] - 1]
             end
      x = [[x, 0].max, @width - Text.width(text, ambiguous_width: @ambiguous_width)].min
      y = [[y, 0].max, @height - 1].min
      while label_conflict?(x, y, text)
        if @horizontal
          y += 1
          @height = [@height, y + 1].max
        else
          x += 1
          @width = [@width, x + Text.width(text, ambiguous_width: @ambiguous_width)].max
        end
      end
      @items << Scene::Text.new(x: x, y: y, string: text, role: :edge_label, layer: :label, emphasis: nil)
    end

    def label_conflict?(x, y, text)
      right = x + Text.width(text, ambiguous_width: @ambiguous_width)
      @ast.nodes.any? do |node|
        nx, ny = @positions.fetch(node.id)
        nw, nh = @sizes.fetch(node.id)
        y.between?(ny, ny + nh - 1) && right > nx && x < nx + nw
      end || @items.any? do |item|
        item.is_a?(Scene::Text) && item.role == :edge_label && item.y == y &&
          right > item.x && x < item.x + Text.width(item.string, ambiguous_width: @ambiguous_width)
      end
    end

    def add_subgraphs
      @group_rects = {}
      @ast.subgraphs.each do |group|
        members = group.node_ids.uniq.filter_map { |id| @positions[id] && [@positions[id], @sizes[id]] }
        next if members.empty?

        padding = 2 * (@max_group_depth - group_depth(group) + 1)
        left = members.map { |(x, _), _| x }.min - padding
        top = members.map { |(_, y), _| y }.min - padding - 1
        right = members.map { |(x, _), (w, _)| x + w }.max + padding - 1
        bottom = members.map { |(_, y), (_, h)| y + h }.max + padding - 1
        next if left.negative? || top.negative? || right >= @width || bottom >= @height

        rect = Scene::Rect.new(x: left, y: top, width: right - left + 1, height: bottom - top + 1)
        @group_rects[group.id] = rect
        @items << Scene::Box.new(rect: rect,
                                 stroke: Scene::LIGHT, corners: :sharp, role: :container_border, layer: :container)
        @items << Scene::Text.new(x: left + 2, y: top + 1, string: group.label, role: :container_title,
                                  layer: :label, emphasis: nil)
      end
    end

    def clip_group_edges
      @ast.edges.each do |edge|
        groups = @ast.styles["group_edge:#{edge.id}"]
        index = @edge_item_indices[edge.id]
        next unless groups && index

        points = @items[index].points
        points = clip_from_group(points, @group_rects[groups[0]]) if groups[0]
        points = clip_from_group(points.reverse, @group_rects[groups[1]]).reverse if groups[1]
        @items[index] = @items[index].with(points: points)
      end
    end

    def clip_from_group(points, rect)
      return points unless rect

      inside = ->(x, y) { x.between?(rect.x, rect.x + rect.width - 1) && y.between?(rect.y, rect.y + rect.height - 1) }
      index = points.each_cons(2).find_index { |a, b| inside.call(*a) && !inside.call(*b) }
      return points unless index

      a, b = points[index, 2]
      x = b[0] < rect.x ? rect.x : b[0] >= rect.x + rect.width ? rect.x + rect.width - 1 : a[0]
      y = b[1] < rect.y ? rect.y : b[1] >= rect.y + rect.height ? rect.y + rect.height - 1 : a[1]
      [[x, y]] + points[(index + 1)..]
    end

    def group_depth(group)
      depth = 0
      parent = group.parent
      visited = []
      while parent
        break if visited.include?(parent)

        visited << parent
        depth += 1
        parent = @ast.subgraphs.find { |candidate| candidate.id == parent }&.parent
      end
      depth
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

    def css_color(style, property)
      style.to_s[/\b#{property}\s*:\s*(\#(?:[\da-fA-F]{3}|[\da-fA-F]{6}))\b/, 1]
    end
  end
end
