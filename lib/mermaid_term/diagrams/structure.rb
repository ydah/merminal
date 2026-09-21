# frozen_string_literal: true

module MermaidTerm::Diagrams
  # Mutable construction of graphs shared by structural diagram parsers.
  class Structure
    attr_reader :nodes, :edges, :subgraphs, :styles

    def initialize
      @nodes = {}
      @edges = []
      @subgraphs = []
      @styles = {}
    end

    def node(id, label: id, shape: :rectangle, line: 1)
      previous = @nodes[id]
      @nodes[id] = Flowchart::Node.new(id: id, label: label || previous&.label || id,
                                       shape: shape || previous&.shape || :rectangle, classes: [], source_pos: [line, 1])
    end

    def edge(from, to, label: nil, stroke: :light, marker: :arrow, line: 1)
      node(from) unless @nodes.key?(from)
      node(to) unless @nodes.key?(to)
      @edges << Flowchart::Edge.new(id: @edges.length, from: from, to: to, label: label, stroke: stroke,
                                    start_marker: nil, end_marker: marker, minlen: 1, source_pos: [line, 1])
    end

    def diagram(direction = :TB)
      Flowchart::Diagram.new(direction: direction, nodes: @nodes.values.freeze, edges: @edges.freeze,
                             subgraphs: @subgraphs.freeze, styles: @styles.freeze)
    end
  end

  def self.endpoint_labels(scene, ast, key)
    edge_lines = scene.items.grep(Scene::Polyline).select { |item| item.role == :edge }
    labels = []
    ast.edges.zip(edge_lines).each do |edge, line|
      values = ast.styles["#{key}:#{edge.id}"]
      next unless values && line

      values.zip([line.points.first, line.points.last]).each_with_index do |(value, point), index|
        next unless value && !value.empty?

        x, y = point
        if ast.direction == :LR || ast.direction == :RL
          x += index.zero? ? 1 : -Text.width(value) - 1
          y -= 1
        else
          x += index.zero? ? -Text.width(value) - 1 : 2
          y += index.zero? ? 1 : -1
        end
        labels << Scene::Text.new(x: [x, 0].max, y: [y, 0].max, string: value, role: :edge_label,
                                  layer: :label, emphasis: nil)
      end
    end
    return scene if labels.empty?

    width = [scene.width, labels.map { |item| item.x + Text.width(item.string) }.max].max
    height = [scene.height, labels.map { |item| item.y + 1 }.max].max
    Scene.new(width: width, height: height, items: (scene.items + labels).freeze)
  end

  # State transitions, choices and composite state frames.
  module State
    def self.diagram_type = :state
    def self.keywords = %w[stateDiagram stateDiagram-v2]

    def self.parse(source)
      graph = Structure.new
      findings = []
      direction = :TB
      stack = []
      notes = []
      open_note = nil
      source.lines.drop(1).each_with_index do |line, index|
        statement = line.strip
        if open_note
          if statement == "end note"
            notes << [open_note[0], open_note[1], open_note[2].join("\n")]
            open_note = nil
          else
            open_note[2] << statement
          end
          next
        end
        case statement
        when /\Adirection\s+(TB|TD|BT|LR|RL)\z/
          direction = Regexp.last_match(1).to_sym
        when /\Astate\s+"([^"]+)"\s+as\s+(\w+)\z/
          id = Regexp.last_match(2)
          graph.node(id, label: Regexp.last_match(1), line: index + 2)
          graph.subgraphs.each { |group| group.node_ids << id if stack.include?(group.id) }
        when /\Astate\s+(\w+)\s*\{\z/
          id = Regexp.last_match(1)
          graph.subgraphs << Flowchart::Subgraph.new(id: id, label: id, node_ids: [], parent: stack.last)
          stack << id
        when /\Astate\s+(\w+)\s+<<(choice|fork|join)>>\z/
          id = Regexp.last_match(1)
          shape = Regexp.last_match(2) == "choice" ? :decision : Regexp.last_match(2).to_sym
          graph.node(id, label: shape == :decision ? id : "", shape: shape)
          graph.subgraphs.each { |group| group.node_ids << id if stack.include?(group.id) }
        when "}"
          stack.pop || findings << MermaidTerm::Diagrams.finding("unexpected state end", source, index + 1)
        when /\A(\[\*\]|[\w.-]+)\s*-->\s*(\[\*\]|[\w.-]+)(?:\s*:\s*(.+))?\z/
          from, to, label = Regexp.last_match.captures
          scope = stack.empty? ? "" : ":#{stack.join(':')}"
          from = "__start#{scope}" if from == "[*]"
          to = "__end#{scope}" if to == "[*]"
          graph.node(from, label: "●", shape: :circle) if from.start_with?("__start")
          graph.node(to, label: "◉", shape: :circle) if to.start_with?("__end")
          graph.edge(from, to, label: label, line: index + 2)
          graph.subgraphs.each { |group| group.node_ids.concat([from, to]) if stack.include?(group.id) }
        when /\Anote\s+(left|right)\s+of\s+([\w.-]+)\s*:\s*(.+)\z/i
          notes << [Regexp.last_match(1).downcase, Regexp.last_match(2), Regexp.last_match(3)]
        when /\Anote\s+(left|right)\s+of\s+([\w.-]+)\z/i
          open_note = [Regexp.last_match(1).downcase, Regexp.last_match(2), []]
        when "end note"
          findings << MermaidTerm::Diagrams.finding("unexpected end note", source, index + 1)
        when ""
          next
        else
          findings << MermaidTerm::Diagrams.finding("unrecognized state statement", source, index + 1)
        end
      end
      findings << MermaidTerm::Diagrams.finding("unclosed state note", source, source.lines.length - 1) if open_note
      graph.styles["notes"] = notes unless notes.empty?
      group_ids = graph.subgraphs.map(&:id)
      graph.edges.each do |edge|
        from = group_ids.include?(edge.from) ? edge.from : nil
        to = group_ids.include?(edge.to) ? edge.to : nil
        graph.styles["group_edge:#{edge.id}"] = [from, to] if from || to
      end
      graph.subgraphs.each do |group|
        representative = group.node_ids.first
        next unless representative

        graph.edges.map! do |edge|
          edge.with(from: edge.from == group.id ? representative : edge.from,
                    to: edge.to == group.id ? representative : edge.to)
        end
        graph.nodes.delete(group.id) unless group.node_ids.include?(group.id)
      end
      notes.each do |_, id, _|
        findings << MermaidTerm::Diagrams.finding("unknown state note target #{id}", source, source.lines.length - 1) unless graph.nodes.key?(id)
      end
      findings << MermaidTerm::Diagrams.finding("unclosed composite state", source, source.lines.length - 1) unless stack.empty?
      [graph.diagram(direction), findings]
    end

    def self.layout(ast, **options)
      scene = Flowchart.layout(ast, **options)
      notes = ast.styles["notes"]
      return scene unless notes && !notes.empty?

      visible_nodes = ast.nodes.reject { |node| %i[fork join].include?(node.shape) }
      boxes = visible_nodes.map(&:id).zip(scene.items.grep(Scene::Box).select { |item| item.role == :node_border }).to_h
      left_width = notes.select { |side, _, _| side == "left" }.map do |_, _, content|
        content.split("\n").map { |line| Text.width(line) }.max.to_i + 4
      end.max.to_i
      shift = left_width.positive? ? left_width + 3 : 0
      items = scene.items.map { |item| Scene.translate(item, dx: shift) }
      width = scene.width + shift
      height = scene.height
      bottoms = { "left" => 0, "right" => 0 }
      notes.each do |side, id, content|
        target = boxes[id]&.rect
        next unless target

        lines = content.split("\n")
        note_width = lines.map { |line| Text.width(line) }.max.to_i + 4
        note_height = lines.length + 2
        x = side == "left" ? 0 : scene.width + shift + 2
        y = [target.y, bottoms[side]].max
        bottoms[side] = y + note_height + 1
        items << Scene::Box.new(rect: Scene::Rect.new(x: x, y: y, width: note_width, height: note_height),
                                stroke: Scene::LIGHT, corners: :sharp, role: :container_border, layer: :container)
        lines.each_with_index do |line, index|
          items << Scene::Text.new(x: x + 2, y: y + 1 + index, string: line, role: :node_text, layer: :label, emphasis: nil)
        end
        center_y = target.y + target.height / 2
        points = side == "left" ? [[x + note_width - 1, y + note_height / 2], [target.x + shift, center_y]] :
                                  [[target.x + shift + target.width - 1, center_y], [x, y + note_height / 2]]
        bend = (points.first[0] + points.last[0]) / 2
        items << Scene::Polyline.new(points: [points.first, [bend, points.first[1]], [bend, points.last[1]], points.last],
                                     stroke: Scene::LIGHT, role: :edge, layer: :edge)
        width = [width, x + note_width].max
        height = [height, y + note_height].max
      end
      Scene.new(width: width, height: height, items: items.freeze)
    end
  end

  # Class diagrams with compartmented boxes and relation endpoints.
  module ClassDiagram
    def self.diagram_type = :class
    def self.keywords = %w[classDiagram]

    def self.parse(source)
      graph = Structure.new
      findings = []
      bodies = Hash.new { |hash, key| hash[key] = [] }
      annotations = {}
      current = nil
      source.lines.drop(1).each_with_index do |line, index|
        statement = line.strip
        if current
          if statement == "}"
            current = nil
          else
            bodies[current] << statement unless statement.empty?
          end
          next
        end
        case statement
        when /\Aclass\s+([\w.-]+)\s*\{\z/
          current = Regexp.last_match(1)
          graph.node(current)
        when /\A(?:class\s+)?([\w.-]+)\s+<<([\w.-]+)>>\z/
          id, annotation = Regexp.last_match.captures
          graph.node(id)
          annotations[id] = annotation
        when /\Aclass\s+([\w.-]+)\z/
          graph.node(Regexp.last_match(1))
        when /\A([\w.-]+)\s*:\s*(.+)\z/
          bodies[Regexp.last_match(1)] << Regexp.last_match(2)
          graph.node(Regexp.last_match(1))
        when /\A([\w.-]+)(?:\s+"([^"]+)")?\s+(<\|--|--\|>|\*--|--\*|o--|--o|\.\.\|>|<\|\.\.|\.\.>|<\.\.|-->|<--|--|\.\.)(?:\s+"([^"]+)")?\s+([\w.-]+)(?:\s*:\s*(.+))?\z/
          left, left_mult, relation, right_mult, right, label = Regexp.last_match.captures
          marker = relation.include?("|") ? :triangle : relation.include?("*") ? :diamond : relation.include?("o") ? :open_diamond : relation.include?(">") || relation.include?("<") ? :arrow : nil
          from, to = relation.start_with?("<") || relation.start_with?("*") || relation.start_with?("o") ? [right, left] : [left, right]
          graph.edge(from, to, label: label, stroke: relation.include?(".") ? :dotted : :light, marker: marker, line: index + 2)
          graph.styles["mult:#{graph.edges.length - 1}"] = from == left ? [left_mult, right_mult] : [right_mult, left_mult]
        when ""
          next
        else
          findings << MermaidTerm::Diagrams.finding("unrecognized class statement", source, index + 1)
        end
      end
      findings << MermaidTerm::Diagrams.finding("unclosed class body", source, source.lines.length - 1) if current
      graph.nodes.each do |id, node|
        body = bodies[id]
        attributes, operations = body.partition { |item| !item.include?("(") }
        name = annotations[id] ? "<<#{annotations[id]}>>\n#{id}" : node.label
        graph.node(id, label: ([name, ""] + (attributes.empty? ? [" "] : attributes) +
                               [""] + (operations.empty? ? [" "] : operations)).join("\n"), shape: :rectangle)
      end
      [graph.diagram, findings]
    end

    def self.layout(ast, **options)
      scene = Flowchart.layout(ast, **options)
      boxes = scene.items.grep(Scene::Box).select { |item| item.role == :node_border }
      dividers = ast.nodes.zip(boxes).flat_map do |node, box|
        rect = box.rect
        rows = node.label.split("\n", -1).flat_map do |line|
          line.empty? ? [true] : Text.wrap(line, options.fetch(:max_label_width, 24),
                                                  ambiguous_width: options.fetch(:ambiguous_width, 1)).map { false }
        end
        rows.each_with_index.filter_map do |divider, index|
          next unless divider

          y = rect.y + index + 1
          Scene::Polyline.new(points: [[rect.x, y], [rect.x + rect.width - 1, y]],
                              stroke: Scene::LIGHT, role: :node_border, layer: :node)
        end
      end
      MermaidTerm::Diagrams.endpoint_labels(scene.with(items: (scene.items + dividers).freeze), ast, "mult")
    end
  end

  # Entity relationship diagrams with attribute tables.
  module ER
    CARDINALITY = { "||" => "1", "o|" => "0..1", "|o" => "0..1", "|{" => "1..*", "}|" => "1..*",
                    "o{" => "0..*", "}o" => "0..*" }.freeze
    def self.diagram_type = :er
    def self.keywords = %w[erDiagram]

    def self.parse(source)
      graph = Structure.new
      findings = []
      current = nil
      attributes = Hash.new { |hash, key| hash[key] = [] }
      source.lines.drop(1).each_with_index do |line, index|
        statement = line.strip
        if current
          if statement == "}"
            current = nil
          elsif !statement.empty?
            attributes[current] << statement.gsub(/\s+/, " ")
          end
          next
        end
        case statement
        when /\A([\w.-]+)\s*\{\z/
          current = Regexp.last_match(1)
          graph.node(current)
        when /\A([\w.-]+)\s+([|o{}]{2})(--|\.\.)([|o{}]{2})\s+([\w.-]+)\s*:\s*(.*)\z/
          from, left, stroke, right, to, text = Regexp.last_match.captures
          graph.edge(from, to, label: text, stroke: stroke == ".." ? :dotted : :light, marker: nil, line: index + 2)
          graph.styles["card:#{graph.edges.length - 1}"] = [CARDINALITY[left] || left, CARDINALITY[right] || right]
        when ""
          next
        else
          findings << MermaidTerm::Diagrams.finding("unrecognized ER statement", source, index + 1)
        end
      end
      findings << MermaidTerm::Diagrams.finding("unclosed entity body", source, source.lines.length - 1) if current
      attributes.each { |id, rows| graph.node(id, label: ([id, ""] + rows).join("\n")) }
      [graph.diagram, findings]
    end

    def self.layout(ast, **options)
      MermaidTerm::Diagrams.endpoint_labels(ClassDiagram.layout(ast, **options), ast, "card")
    end
  end
end
