# frozen_string_literal: true

module MermaidTerm::Diagrams
  # Indented Mermaid mindmap rendered as a tidy tree.
  module Mindmap
    Node = Data.define(:id, :label, :parent, :depth, :shape)
    Diagram = Data.define(:nodes)
    def self.diagram_type = :mindmap
    def self.keywords = %w[mindmap]

    def self.parse(source)
      nodes = []
      stack = []
      findings = []
      source.lines.drop(1).each_with_index do |line, index|
        next if line.strip.empty?

        indent = line[/\A\s*/].length
        while stack.any? && stack.last[0] >= indent
          stack.pop
        end
        if nodes.any? && stack.empty?
          findings << MermaidTerm::Diagrams.finding("mindmap node has no parent", source, index + 1)
          next
        end
        raw = line.strip
        shape, label = if raw =~ /\A(.+?)\(\((.+)\)\)\z/
                         [:circle, Regexp.last_match(2)]
                       elsif raw =~ /\A(.+?)\[(.+)\]\z/
                         [:rectangle, Regexp.last_match(2)]
                       elsif raw =~ /\A(.+?)\((.+)\)\z/
                         [:rounded, Regexp.last_match(2)]
                       else
                         [:rectangle, raw]
                       end
        id = nodes.length
        nodes << Node.new(id: id, label: label, parent: stack.last&.last, depth: stack.length, shape: shape)
        stack << [indent, id]
      end
      [Diagram.new(nodes: nodes.freeze), findings]
    end

    def self.layout(ast, **)
      builder = Builder.new
      return builder.scene if ast.nodes.empty?

      children = ast.nodes.to_h { |node| [node.id, []] }
      ast.nodes.each { |node| children[node.parent] << node.id if node.parent }
      depth_widths = ast.nodes.group_by(&:depth).transform_values do |nodes|
        nodes.map { |node| Text.width(node.label) + 4 }.max
      end
      x_positions = {}
      depth_widths.keys.sort.each { |depth| x_positions[depth] = depth.zero? ? 0 : x_positions[depth - 1] + depth_widths[depth - 1] + 5 }
      y_positions = {}
      next_leaf = 0
      place = lambda do |id|
        if children[id].empty?
          y_positions[id] = next_leaf * 4
          next_leaf += 1
        else
          children[id].each { |child| place.call(child) }
          y_positions[id] = (y_positions[children[id].first] + y_positions[children[id].last]) / 2
        end
      end
      place.call(ast.nodes.first.id)
      ast.nodes.each do |node|
        x, y = x_positions[node.depth], y_positions[node.id]
        width = Text.width(node.label) + 4
        builder.box(x, y, width, 3, rounded: node.shape != :rectangle)
        builder.text(x + 2, y + 1, node.label)
        next unless node.parent

        parent = ast.nodes[node.parent]
        px = x_positions[parent.depth] + Text.width(parent.label) + 3
        py = y_positions[parent.id] + 1
        cy = y + 1
        middle = (px + x) / 2
        builder.line([[px, py], [middle, py], [middle, cy], [x, cy]])
      end
      builder.scene
    end
  end
end
