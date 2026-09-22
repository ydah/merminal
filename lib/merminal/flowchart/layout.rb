# frozen_string_literal: true

module Merminal::Flowchart
  Scene = Merminal::Scene
  Text = Merminal::Text

  # Deterministic layered placement with channel routing.
  class Layout
    WorkNode = Data.define(:id, :kind, :label, :edge_id, :source, :target)

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
      normalize_edges
      order_nodes
      place_nodes
      draw_nodes
      draw_edges
      add_subgraphs
      avoid_unrelated_groups
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

          distance = edge.label && !edge.label.empty? ? edge.minlen * 2 : edge.minlen
          @ranks[to] = [@ranks[to], @ranks[id] + distance].max
          indegree[to] -= 1
          queue << to if indegree[to].zero?
        end
      end
      # A malformed cycle can survive DFS when parallel edges are involved.
      @ranks.keys.each { |id| @ranks[id] = 0 if indegree[id].positive? }
    end

    def normalize_edges
      @work_nodes = @ast.nodes.dup
      @segments = []
      @edge_paths = {}
      @membership = @ast.nodes.to_h do |node|
        [node.id, @ast.subgraphs.select { |group| group.node_ids.include?(node.id) }.map(&:id)]
      end
      @oriented.each do |edge, from, to, _|
        next if from == to

        gap = @ranks[to] - @ranks[from]
        path = [from]
        if gap > 1
          middle = @ranks[from] + gap / 2
          (@ranks[from] + 1...@ranks[to]).each do |rank|
            kind = edge.label && !edge.label.empty? && rank == middle ? :label : :dummy
            id = "\0#{edge.id}:#{rank}"
            node = WorkNode.new(id: id, kind: kind, label: kind == :label ? edge.label : nil,
                                edge_id: edge.id, source: from, target: to)
            @work_nodes << node
            @ranks[id] = rank
            @membership[id] = @membership.fetch(from, []) & @membership.fetch(to, [])
            path << id
          end
        end
        path << to
        @edge_paths[edge.id] = path
        path.each_cons(2) { |a, b| @segments << [edge, a, b] }
      end
      @work_node_by_id = @work_nodes.grep(WorkNode).to_h { |node| [node.id, node] }
    end

    def order_nodes
      @groups = @work_nodes.group_by { |node| @ranks[node.id] }

      best = @groups.transform_values(&:dup)
      best_crossings = crossing_count
      stalled = 0
      8.times do |pass|
        downward = pass.even?
        ranks = downward ? @groups.keys.sort : @groups.keys.sort.reverse
        ranks.each do |rank|
          neighbor_rank = rank + (downward ? -1 : 1)
          adjacent = @groups[neighbor_rank]
          next unless adjacent

          positions = adjacent.each_with_index.to_h { |node, index| [node.id, index] }
          scores = @groups[rank].to_h do |node|
            neighbors = @segments.filter_map do |_, from, to|
              if downward && to == node.id && @ranks[from] == neighbor_rank
                positions[from]
              elsif !downward && from == node.id && @ranks[to] == neighbor_rank
                positions[to]
              end
            end.sort
            median = neighbors.empty? ? nil : (neighbors[(neighbors.length - 1) / 2] + neighbors[neighbors.length / 2]) / 2.0
            [node.id, median]
          end
          @groups[rank] = sort_clustered(@groups[rank], scores)
        end
        count = crossing_count
        if count < best_crossings
          best = @groups.transform_values(&:dup)
          best_crossings = count
          stalled = 0
        else
          stalled += 1
          break if stalled >= 2
        end
      end
      @groups = best
    end

    def sort_clustered(nodes, scores, parent = nil, seen = [])
      children = @ast.subgraphs.select { |group| group.parent == parent && !seen.include?(group.id) }
      blocks = []
      nodes.each do |node|
        group = children.find { |candidate| @membership.fetch(node.id, []).include?(candidate.id) }
        block = group && blocks.find { |entry| entry[:group] == group.id }
        if block
          block[:nodes] << node
        else
          blocks << { group: group&.id, nodes: [node], index: blocks.length }
        end
      end
      blocks.sort_by! do |block|
        values = block[:nodes].filter_map { |node| scores[node.id] }.sort
        median = values.empty? ? block[:index] : (values[(values.length - 1) / 2] + values[values.length / 2]) / 2.0
        [median, block[:index]]
      end
      blocks.flat_map do |block|
        block[:group] ? sort_clustered(block[:nodes], scores, block[:group], seen + [block[:group]]) : block[:nodes]
      end
    end

    def crossing_count
      positions = @groups.transform_values { |nodes| nodes.each_with_index.to_h { |node, index| [node.id, index] } }
      by_rank = Hash.new { |hash, rank| hash[rank] = [] }
      @segments.each do |_, from, to|
        rank = @ranks[from]
        next unless @ranks[to] == rank + 1

        by_rank[rank] << [positions[rank][from], positions[rank + 1][to]]
      end
      by_rank.sum do |rank, edges|
        tree = Array.new(@groups[rank + 1].length + 2, 0)
        seen = 0
        edges.sort_by { |from, to| [from, to] }.sum do |_, to|
          index = to + 1
          smaller_or_equal = 0
          while index.positive?
            smaller_or_equal += tree[index]
            index -= index & -index
          end
          crossings = seen - smaller_or_equal
          index = to + 1
          while index < tree.length
            tree[index] += 1
            index += index & -index
          end
          seen += 1
          crossings
        end
      end
    end

    def place_nodes
      @labels = @ast.nodes.to_h do |node|
        [node.id, Merminal::Text.wrap(node.label, @max_label_width, ambiguous_width: @ambiguous_width)]
      end
      @sizes = @ast.nodes.to_h do |node|
        width = @labels[node.id].map { |line| Merminal::Text.width(line, ambiguous_width: @ambiguous_width) }.max.to_i + @padding * 2 + 2
        width += 2 if %i[circle double_circle decision hexagon subroutine].include?(node.shape)
        height = @labels[node.id].length + 2 + (node.shape == :database ? 1 : 0)
        width = [width, 9].max if %i[fork join].include?(node.shape)
        height = [height, 5].max if @horizontal && %i[fork join].include?(node.shape)
        incoming = @segments.count { |_, from, to| to == node.id && from != to }
        @horizontal ? height = [height, incoming + 2].max : width = [width, incoming + 2].max
        [node.id, [width, height]]
      end
      @work_nodes.grep(WorkNode).each do |node|
        @sizes[node.id] = if node.kind == :label
                            [Text.width(node.label, ambiguous_width: @ambiguous_width) + 2, @horizontal ? 2 : 1]
                          else
                            [1, 1]
                          end
      end
      @positions = {}
      order_positions = @ast.subgraphs.empty? ? nil : group_band_positions
      ranks = @groups.keys.sort
      cursor = 3 + @cluster_margin
      ranks.each do |rank|
        order = 1 + @cluster_margin
        @groups[rank].each do |node|
          width, height = @sizes.fetch(node.id)
          node_order = order_positions ? order_positions.fetch(node.id) : order
          @positions[node.id] = @horizontal ? [cursor, node_order] : [node_order, cursor]
          order += (@horizontal ? height : width) + @node_gap
        end
        cursor += @groups[rank].map { |node| @horizontal ? @sizes[node.id][0] : @sizes[node.id][1] }.max.to_i
      end
      align_order_positions if @ast.subgraphs.empty?
      @input_ports = {}
      @ast.nodes.each do |node|
        incoming = @segments.select { |_, from, to| to == node.id && from != to }
        incoming.sort_by! { |edge, from, _| [@horizontal ? @positions[from][1] : @positions[from][0], edge.id] }
        dimension = @horizontal ? @sizes[node.id][1] : @sizes[node.id][0]
        @input_ports[node.id] = incoming.each_with_index.to_h do |(edge, _, _), index|
          [edge.id, ((dimension - 1) * (index + 1).to_f / (incoming.length + 1)).round]
        end
      end
      allocate_channel_tracks
      cursor = 3 + @cluster_margin
      ranks.each_with_index do |rank, index|
        if index.positive?
          previous = ranks[index - 1]
          cursor += [@rank_gap, @track_count.fetch(previous, 0) * 2 + 2].max
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
      @oriented.each do |edge, _, _, _|
        next if @edge_paths[edge.id]

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

    def align_order_positions
      @groups.each_value do |nodes|
        sizes = nodes.map { |node| @horizontal ? @sizes.fetch(node.id)[1] : @sizes.fetch(node.id)[0] }
        positions = nodes.map { |node| @horizontal ? @positions.fetch(node.id)[1] : @positions.fetch(node.id)[0] }
        fixed = nodes.each_index.reject { |index| nodes[index].is_a?(WorkNode) }
        movable = nodes.each_index.select { |index| nodes[index].is_a?(WorkNode) }
        movable.sort_by { |index| [nodes[index].kind == :dummy ? 0 : 1, index] }.each do |index|
          node = nodes[index]
          anchors = [node.source, node.target].map do |id|
            coordinate = @horizontal ? @positions.fetch(id)[1] : @positions.fetch(id)[0]
            coordinate + (@horizontal ? @sizes.fetch(id)[1] : @sizes.fetch(id)[0]) / 2
          end
          target = (anchors.sum / 2.0).round - (@horizontal && node.kind == :label ? 1 : 0)
          trial = positions.dup
          trial[index] = target
          (index - 1).downto(0) do |cursor|
            trial[cursor] = [trial[cursor], trial[cursor + 1] - sizes[cursor] - @node_gap].min
          end
          (index + 1...trial.length).each do |cursor|
            trial[cursor] = [trial[cursor], trial[cursor - 1] + sizes[cursor - 1] + @node_gap].max
          end
          next if trial.min < 1 || fixed.any? { |cursor| trial[cursor] != positions[cursor] }

          positions = trial
          fixed << index
        end
        nodes.each_with_index do |node, index|
          point = @positions.fetch(node.id)
          @positions[node.id] = @horizontal ? [point[0], positions[index]] : [positions[index], point[1]]
        end
      end
    end

    def group_band_positions
      indices = @work_nodes.each_with_index.to_h { |node, index| [node.id, index] }
      groups = @ast.subgraphs.select { |group| !group.parent && group.node_ids.any? }
      ranges = groups.to_h do |group|
        members = @work_nodes.filter_map { |node| indices[node.id] if @membership.fetch(node.id, []).include?(group.id) }
        [group.id, [members.min, members.max]]
      end
      groups.sort_by! { |group| ranges[group.id].first }
      keys = @work_nodes.to_h do |node|
        group = groups.find { |candidate| @membership.fetch(node.id, []).include?(candidate.id) }
        slot = groups.count { |candidate| ranges[candidate.id].last < indices[node.id] }
        [node.id, group ? [:group, group.id] : [:outside, slot]]
      end
      order = (0..groups.length).flat_map do |slot|
        [[:outside, slot], ([:group, groups[slot].id] if groups[slot])].compact
      end
      widths = order.to_h { |key| [key, 0] }
      @groups.each_value do |nodes|
        nodes.group_by { |node| keys[node.id] }.each do |key, members|
          size = members.sum { |node| @horizontal ? @sizes[node.id][1] : @sizes[node.id][0] } +
                 [members.length - 1, 0].max * @node_gap
          widths[key] = [widths[key], size].max
        end
      end
      groups.each do |group|
        key = [:group, group.id]
        widths[key] = [widths[key], Text.width(group.label) + @cluster_margin * 2 + 4].max
      end
      order.select! { |key| widths[key].positive? }
      starts = {}
      cursor = 1 + @cluster_margin
      order.each do |key|
        starts[key] = cursor
        cursor += widths[key] + @node_gap + @cluster_margin * 2
      end
      @groups.values.flatten.to_h do |node|
        key = keys.fetch(node.id)
        peers = @groups.fetch(@ranks.fetch(node.id)).select { |candidate| keys[candidate.id] == key }
        before = peers.take_while { |candidate| candidate.id != node.id }
        offset = before.sum { |candidate| @horizontal ? @sizes[candidate.id][1] : @sizes[candidate.id][0] } +
                 before.length * @node_gap
        [node.id, starts.fetch(key) + offset]
      end
    end

    def allocate_channel_tracks
      intervals = Hash.new { |hash, rank| hash[rank] = {} }
      @segments.each do |edge, from, to|
        next unless @ranks[to] - @ranks[from] == 1

        rank = @ranks[from]
        a = port(from)
        b = port(to, end_port: true, edge_id: edge.id)
        next if (@horizontal ? a[1] == b[1] : a[0] == b[0])

        left, right = [@horizontal ? a[1] : a[0], @horizontal ? b[1] : b[0]].minmax
        key = from
        group = intervals[rank][key] ||= { left: left, right: right, edges: [] }
        group[:left] = [group[:left], left].min
        group[:right] = [group[:right], right].max
        group[:edges] << [edge.id, rank]
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
      @edge_label_indices = {}
      @oriented.each do |edge, from, to, _reversed|
        next if edge.stroke == :invisible

        path = @edge_paths[edge.id]
        if path
          points = path.each_cons(2).flat_map do |a, b|
            channel_route(a, b, @track_for_edge[[edge.id, @ranks[a]]], edge.id)
          end
          points = points.chunk_while { |a, b| a == b }.map(&:first)
        else
          points = outer_route(from, to, @outer_offsets.fetch(edge.id), edge.id)
        end
        stroke = Scene::Stroke.new(weight: edge.stroke == :heavy ? :heavy : :light,
                                   pattern: edge.stroke == :dotted ? :dotted : :solid)
        style = @ast.styles["link:#{edge.id}"] || @ast.styles["link:default"]
        color = css_color(style, "stroke")
        @edge_item_indices[edge.id] = @items.length
        @items << Scene::Polyline.new(points: points, stroke: stroke, role: color ? :"fg:#{color}" : :edge, layer: :edge)
        if edge.label && !edge.label.empty?
          @edge_label_indices[edge.id] = @items.length
          label_node = path&.find { |id| @work_node_by_id[id]&.kind == :label }
          if label_node
            x, y = @positions.fetch(label_node)
            @items << Scene::Text.new(x: x + 1, y: y, string: edge.label, role: :edge_label, layer: :label, emphasis: nil)
          else
            label_edge(edge, points)
          end
        end
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
      work_node = @work_node_by_id[id]
      if work_node
        return @horizontal ? [end_port ? x : x + w - 1, y + (work_node.kind == :label ? 1 : 0)] : [x, y]
      end
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
      return [a, b] if @horizontal ? a[1] == b[1] : a[0] == b[0]

      middle = @rank_ends.fetch(@ranks[from]) + 2 + track * 2
      if @horizontal
        [a, [middle, a[1]], [middle, b[1]], b]
      else
        [a, [a[0], middle], [b[0], middle], b]
      end
    end

    def outer_route(from, to, offset, edge_id)
      # ponytail: self loops use outside lanes; add a dedicated loop primitive if dense graphs need tighter layouts.
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
      end_tip, end_neighbor = reversed ? points.first(2) : points.last(2).reverse
      start_tip, start_neighbor = reversed ? points.last(2).reverse : points.first(2)
      put_marker(end_tip, edge.end_marker, tip_direction(end_tip, end_neighbor))
      put_marker(start_tip, edge.start_marker, tip_direction(start_tip, start_neighbor))
    end

    def tip_direction(tip, neighbor)
      return tip[0] > neighbor[0] ? :e : :w if tip[0] != neighbor[0]

      tip[1] > neighbor[1] ? :s : :n
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
        right = [right, left + Text.width(group.label) + 3].max
        bottom = members.map { |(_, y), (_, h)| y + h }.max + padding - 1
        next if left.negative? || top.negative?

        @width = [@width, right + 1].max
        @height = [@height, bottom + 1].max

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

    def avoid_unrelated_groups
      detours = 0
      @ast.edges.each do |edge|
        index = @edge_item_indices[edge.id]
        next unless index

        line = @items[index]
        blocked = @ast.subgraphs.any? do |group|
          rect = @group_rects[group.id]
          rect && !group.node_ids.include?(edge.from) && !group.node_ids.include?(edge.to) &&
            crosses_frame?(line.points, rect)
        end
        next unless blocked

        lane = @group_rects.values.map { |rect| rect.y + rect.height }.max + 2 + detours * 2
        detours += 1
        a = line.points.first
        target = @oriented.find { |candidate| candidate.first.id == edge.id }[2]
        tx, ty = @positions.fetch(target)
        tw, th = @sizes.fetch(target)
        b = @horizontal ? [tx + tw / 2, ty + th - 1] : [line.points.last[0], ty + th - 1]
        @items[index] = line.with(points: [a, [a[0], lane], [b[0], lane], b])
        @height = [@height, lane + 1].max
        label_index = @edge_label_indices[edge.id]
        next unless label_index

        label = @items[label_index]
        x = [(a[0] + b[0] - Text.width(label.string, ambiguous_width: @ambiguous_width)) / 2, 0].max
        @items[label_index] = label.with(x: x, y: lane - 1)
      end
    end

    def crosses_frame?(points, rect)
      points.each_cons(2).any? do |(x1, y1), (x2, y2)|
        if x1 == x2
          x1 > rect.x && x1 < rect.x + rect.width - 1 &&
            [y1, y2].max > rect.y && [y1, y2].min < rect.y + rect.height - 1
        else
          y1 > rect.y && y1 < rect.y + rect.height - 1 &&
            [x1, x2].max > rect.x && [x1, x2].min < rect.x + rect.width - 1
        end
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
