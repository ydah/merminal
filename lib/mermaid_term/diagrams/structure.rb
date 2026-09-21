# frozen_string_literal: true

module MermaidTerm::Diagrams
  # Mutable construction of graphs shared by structural diagram parsers.
  class Structure
    attr_reader :nodes, :edges, :subgraphs

    def initialize
      @nodes = {}
      @edges = []
      @subgraphs = []
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
                             subgraphs: @subgraphs.freeze, styles: {}.freeze)
    end
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
      source.lines.drop(1).each_with_index do |line, index|
        statement = line.strip
        case statement
        when /\Adirection\s+(TB|TD|BT|LR|RL)\z/
          direction = Regexp.last_match(1).to_sym
        when /\Astate\s+"([^"]+)"\s+as\s+(\w+)\z/
          graph.node(Regexp.last_match(2), label: Regexp.last_match(1), line: index + 2)
        when /\Astate\s+(\w+)\s*\{\z/
          id = Regexp.last_match(1)
          graph.node(id)
          graph.subgraphs << Flowchart::Subgraph.new(id: id, label: id, node_ids: [], parent: stack.last)
          stack << id
        when /\Astate\s+(\w+)\s+<<(choice|fork|join)>>\z/
          graph.node(Regexp.last_match(1), shape: Regexp.last_match(2) == "choice" ? :decision : :rounded)
        when "}"
          stack.pop || findings << Diagrams.finding("unexpected state end", source, index + 1)
        when /\A(\[\*\]|[\w.-]+)\s*-->\s*(\[\*\]|[\w.-]+)(?:\s*:\s*(.+))?\z/
          from, to, label = Regexp.last_match.captures
          from = "__start" if from == "[*]"
          to = "__end" if to == "[*]"
          graph.node(from, label: "●", shape: :circle) if from == "__start"
          graph.node(to, label: "◉", shape: :circle) if to == "__end"
          graph.edge(from, to, label: label, line: index + 2)
          group = graph.subgraphs.find { |item| item.id == stack.last }
          group&.node_ids&.concat([from, to]) if group
        when /\A(?:note|end note)\b/i
          findings << Diagrams.finding("state note ignored", source, index + 1, severity: :info)
        when ""
          next
        else
          findings << Diagrams.finding("unrecognized state statement", source, index + 1)
        end
      end
      findings << Diagrams.finding("unclosed composite state", source, source.lines.length - 1) unless stack.empty?
      [graph.diagram(direction), findings]
    end

    def self.layout(ast, **options)
      Flowchart.layout(ast, **options)
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
        when /\Aclass\s+([\w.-]+)\z/
          graph.node(Regexp.last_match(1))
        when /\A([\w.-]+)\s*:\s*(.+)\z/
          bodies[Regexp.last_match(1)] << Regexp.last_match(2)
          graph.node(Regexp.last_match(1))
        when /\A([\w.-]+)\s+(<\|--|--\|>|\*--|--\*|o--|--o|\.\.\|>|<\|\.\.|\.\.>|<\.\.|-->|<--|--|\.\.)\s+([\w.-]+)(?:\s*:\s*(.+))?\z/
          left, relation, right, label = Regexp.last_match.captures
          marker = relation.include?("|") ? :triangle : relation.include?("*") ? :diamond : relation.include?("o") ? :open_diamond : relation.include?(">") || relation.include?("<") ? :arrow : nil
          from, to = relation.start_with?("<") || relation.start_with?("*") || relation.start_with?("o") ? [right, left] : [left, right]
          graph.edge(from, to, label: label, stroke: relation.include?(".") ? :dotted : :light, marker: marker, line: index + 2)
        when /\A[\w.-]+\s+<<.+>>\z/, ""
          next
        else
          findings << Diagrams.finding("unrecognized class statement", source, index + 1)
        end
      end
      findings << Diagrams.finding("unclosed class body", source, source.lines.length - 1) if current
      graph.nodes.each do |id, node|
        body = bodies[id]
        next if body.empty?

        attributes, operations = body.partition { |item| !item.include?("(") }
        graph.node(id, label: ([node.label, ""] + attributes + (operations.empty? ? [] : [""] + operations)).join("\n"), shape: :rectangle)
      end
      [graph.diagram, findings]
    end

    def self.layout(ast, **options)
      scene = Flowchart.layout(ast, **options)
      boxes = scene.items.grep(Scene::Box).select { |item| item.role == :node_border }
      dividers = ast.nodes.zip(boxes).flat_map do |node, box|
        rect = box.rect
        node.label.split("\n", -1).each_with_index.filter_map do |line, index|
          next unless line.empty?

          y = rect.y + index + 1
          Scene::Polyline.new(points: [[rect.x, y], [rect.x + rect.width - 1, y]],
                              stroke: Scene::LIGHT, role: :node_border, layer: :node)
        end
      end
      scene.with(items: (scene.items + dividers).freeze)
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
          label = [CARDINALITY[left] || left, text, CARDINALITY[right] || right].join(" ")
          graph.edge(from, to, label: label, stroke: stroke == ".." ? :dotted : :light, marker: nil, line: index + 2)
        when ""
          next
        else
          findings << Diagrams.finding("unrecognized ER statement", source, index + 1)
        end
      end
      findings << Diagrams.finding("unclosed entity body", source, source.lines.length - 1) if current
      attributes.each { |id, rows| graph.node(id, label: ([id, ""] + rows).join("\n")) }
      [graph.diagram, findings]
    end

    def self.layout(ast, **options)
      ClassDiagram.layout(ast, **options)
    end
  end
end
