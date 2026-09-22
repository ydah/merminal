# frozen_string_literal: true

module Merminal::Diagrams
  # Native layouts cover each registered syntax; the shared scene is retained
  # only as a compatibility path for incomplete input.
  module Additional
    Diagram = Data.define(:keyword, :title, :lines, :nodes, :edges, :direction)
    Node = Data.define(:id, :label)
    Edge = Data.define(:from, :to, :label)
    DIRECTIONS = Merminal::Flowchart::DIRECTIONS
    EDGE_PATTERN = /(?:<\||<|o|x)?(?:-{2,}|<-|->|\.{2,}|={2,}|~{3,})(?:\|>|>|o|x)?/
    C4_NODE_TYPES = %w[
      Person Person_Ext System System_Ext SystemDb SystemDb_Ext SystemQueue SystemQueue_Ext
      Boundary Enterprise_Boundary System_Boundary Container Container_Ext ContainerDb ContainerDb_Ext
      ContainerQueue ContainerQueue_Ext Container_Boundary Component Component_Ext ComponentDb ComponentDb_Ext
      ComponentQueue ComponentQueue_Ext Deployment_Node Node Node_L Node_R
    ].freeze
    C4_RELATION = /\A(?:Rel(?:_Back|_Up|_Down|_Left|_Right|_U|_D|_L|_R)?|BiRel)\(([^,]+),\s*([^,]+)(?:,\s*["']?([^"')]+)["']?)?/

    KEYWORDS = %w[
      journey quadrantChart requirementDiagram usecaseDiagram usecase-beta gitGraph
      C4Context C4Container C4Component C4Dynamic C4Deployment zenuml
      sankey-beta block-beta packet-beta kanban architecture-beta radar-beta
      treemap-beta venn-beta ishikawa-beta wardley-beta treeView treeView-beta
      cynefin-beta swimlane-beta eventModeling agentflow-beta
      railroad-ebnf-beta railroad-abnf-beta railroad-peg-beta railroad-beta
    ].freeze
    ALIASES = {
      "gitGraph" => %w[gitGraph gitgraph],
      "block-beta" => %w[block-beta block],
      "packet-beta" => %w[packet-beta packet],
      "treeView" => %w[treeView treeview],
      "treeView-beta" => %w[treeView-beta treeview-beta],
      "eventModeling" => %w[eventModeling eventmodeling],
      "agentflow-beta" => %w[agentflow-beta agentflow]
    }.transform_values(&:freeze).freeze

    DECLARATION = /\A(?:participant|actor|class|state|service|interface|component|container|system|person|database|requirement|functionalRequirement|interfaceRequirement|performanceRequirement|physicalRequirement|designConstraint|element|usecase|systemBoundary|json|group|rect|boundary|package|namespace|entity|node|junction)\s+([^\s\[\](){}:]+)(?:\s+as\s+(.+)|\[([^\]]+)\]|\(([^)]+)\))?/i

    module_function

    def plugin(keyword, aliases: [keyword])
      Module.new do
        define_singleton_method(:diagram_type) { keyword.to_s.gsub(/[^a-zA-Z0-9]+/, "_").downcase.to_sym }
        define_singleton_method(:keywords) { aliases }
        define_singleton_method(:parse) { |source| Additional.parse(source, keyword) }
        define_singleton_method(:layout) { |ast, **options| Additional.layout(ast, **options) }
      end
    end

    def parse(source, keyword)
      lines = source.lines.drop(1).map(&:to_s).map(&:rstrip).reject { |line| line.strip.empty? }
      title = source.title
      direction = source.lines.first.to_s.split[1].to_s.delete_suffix(":").then do |value|
        next value.to_sym if DIRECTIONS.include?(value)

        keyword == "gitGraph" ? :LR : :TB
      end
      nodes = {}
      edges = []

      lines.each do |raw_line|
        line = raw_line.strip
        next if keyword == "quadrantChart" && line.match?(/\A[xy]-axis\b/i)

        case line
        when /\Atitle\s+(.+)\z/i
          title ||= unquote(Regexp.last_match(1))
        when /\A(?:direction|layout)\s+(TB|TD|BT|LR|RL)\b/i
          direction = Regexp.last_match(1).to_sym
        else
          if (relations = relation_chain(line))
            relations.each do |from_value, _operator, to_value, edge_label|
              from_id, from_label = endpoint(from_value, nodes.length)
              to_id, to_label = endpoint(to_value, nodes.length + 1)
              nodes[from_id] ||= Node.new(id: from_id, label: from_label)
              nodes[to_id] ||= Node.new(id: to_id, label: to_label)
              edges << Edge.new(from: from_id, to: to_id, label: edge_label)
            end
          elsif (match = line.match(/\A(?:group|service)\s+([[:alnum:]_-]+)(?:\([^)]*\))?\[([^\]]+)\]/i))
            nodes[match[1]] ||= Node.new(id: match[1], label: match[2].strip)
          elsif (node = c4_node(line))
            id, label = node
            nodes[id] ||= Node.new(id: id, label: label)
          elsif (relation = c4_relation(line))
            from_id, to_id, label = relation
            nodes[from_id] ||= Node.new(id: from_id, label: from_id)
            nodes[to_id] ||= Node.new(id: to_id, label: to_id)
            edges << Edge.new(from: from_id, to: to_id, label: label)
          elsif (match = line.match(/\A(?:flow|global|connector)\s+([[:alnum:]_.-]+)(?:\[([^\]]+)\])?/i))
            id = match[1]
            nodes[id] ||= Node.new(id: id, label: match[2].to_s.delete_prefix('"').delete_suffix('"').then { |label| label.empty? ? id : label })
          elsif (match = line.match(/\A([[:alnum:]_.-]+)(?:\[([^\]]+)\]|@\{)/))
            id = match[1]
            label = match[2].to_s.delete_prefix('"').delete_suffix('"')
            nodes[id] ||= Node.new(id: id, label: label.empty? ? id : label)
          elsif (match = line.match(DECLARATION))
            id = match[1]
            label = (match[2] || match[3] || match[4])&.strip&.delete_prefix('"')&.delete_suffix('"') || id
            nodes[id] ||= Node.new(id: id, label: label)
          elsif useful_line?(line)
            id = "line#{nodes.length}"
            nodes[id] = Node.new(id: id, label: raw_line)
          end
        end
      end

      if nodes.empty? && title
        nodes["title"] = Node.new(id: "title", label: title)
      end
      [Diagram.new(keyword: keyword, title: title, lines: lines.freeze, nodes: nodes.values.freeze,
                   edges: edges.freeze, direction: direction), []]
    end

    def unquote(value)
      text = value.to_s.strip
      return text[1...-1] if text.length >= 2 && ['"', "'"].include?(text[0]) && text[-1] == text[0]

      text
    end

    def layout(ast, **options)
      native = Specialized.scene(ast, **options)
      return native if native

      return graph_scene(ast, **options) if ast.edges.any?

      card_scene(ast)
    end

    def graph_scene(ast, **options)
      flow_nodes = ast.nodes.map do |node|
        Merminal::Flowchart::Node.new(id: node.id, label: node.label, shape: :rectangle,
                                         classes: [].freeze, source_pos: [1, 1])
      end
      flow_edges = ast.edges.each_with_index.map do |edge, index|
        Merminal::Flowchart::Edge.new(id: index, from: edge.from, to: edge.to, label: edge.label,
                                         stroke: :light, start_marker: nil, end_marker: :arrow,
                                         minlen: 1, source_pos: [1, 1])
      end
      flow = Merminal::Flowchart::Diagram.new(direction: ast.direction, nodes: flow_nodes.freeze,
                                                 edges: flow_edges.freeze, subgraphs: [].freeze, styles: {}.freeze)
      Merminal::Flowchart.layout(flow, **options)
    end

    def card_scene(ast)
      builder = Builder.new
      y = 0
      if ast.title
        builder.text(0, y, ast.title, role: :emphasis)
        y += 2
      end
      width = [ast.lines.map { |line| Merminal::Text.width(line) }.max.to_i + 4, 12].max
      ast.lines.each_with_index do |line, index|
        builder.box(0, y, width, 3, role: :node_border)
        builder.text(2, y + 1, "#{index + 1}. #{line}")
        y += 4
      end
      builder.scene
    end

    def endpoint(value, index)
      text = value.to_s.strip.sub(/\A<?[TBLR]:/, "").sub(/:[TBLR]\z/, "")
      anonymous = text.match(/\A\((.+)\)\z/)
      label_match = text.match(/\A[^\[]+\[(.+)\]\z/) || text.match(/\A[^\(]+\((.+)\)\z/) || text.match(/\A[\"'](.+)[\"']\z/)
      label = anonymous ? anonymous[1] : label_match ? label_match[1] : text
      id = if anonymous
             anonymous[1].gsub(/\W+/, "_")
           else
             text[/[[:alnum:]_][[:alnum:]_.-]*/]
           end || "node#{index}"
      [id, label.to_s.gsub(/<br\s*\/?\s*>/i, "\n")]
    end

    def c4_relation(line)
      match = line.match(/\ARelIndex\([^,]+,\s*([^,]+),\s*([^,]+)(?:,\s*["']?([^"')]+)["']?)?/)
      match ||= line.match(C4_RELATION)
      return unless match

      [match[1].strip, match[2].strip, match[3]&.strip]
    end

    def c4_node(line)
      match = line.match(/\A([[:alnum:]_]+)\((.*)\)/)
      return unless match && C4_NODE_TYPES.include?(match[1])

      arguments = []
      current = +""
      quote = nil
      match[2].each_char do |char|
        if quote
          quote = nil if quote == char
        elsif ['"', "'"].include?(char)
          quote = char
        end
        if char == "," && quote.nil?
          arguments << current
          current = +""
        else
          current << char
        end
      end
      arguments << current
      return unless arguments[1]

      label = arguments[1].strip
      label = label[1...-1] if label.length >= 2 && ['"', "'"].include?(label[0]) && label[-1] == label[0]
      [arguments[0].strip, label]
    end

    def relation_chain(line)
      if (match = line.match(/\A(.+?)\s+-\s+(.+?)\s+->\s+(.+)\z/))
        return [[match[1], '->', match[3], match[2]]]
      end
      if (match = line.match(/\A(.+?)\s+<-\s+(.+?)\s+-\s+(.+)\z/))
        return [[match[3], '<-', match[1], match[2]]]
      end

      operators = []
      line.scan(EDGE_PATTERN) do
        match = Regexp.last_match
        operators << [match.begin(0), match[0], match.end(0)]
      end
      return if operators.empty?

      from = line[0...operators.first[0]].strip
      pending_label = nil
      operators.filter_map.with_index do |(_, operator, finish), index|
        target_end = operators[index + 1]&.first || line.length
        target = line[finish...target_end].to_s.strip
        next if target.empty?
        if operators[index + 1] && target.match?(/\A["'].*["']\z/)
          pending_label = target[1...-1]
          next
        end

        label = pending_label
        pending_label = nil
        if (pipe = target.match(/\A\|(.+?)\|\s+(.+)\z/))
          label = pipe[1]
          target = pipe[2]
        elsif !target.match?(/\A<?[TBLR]:/) && !target.match?(/:[TBLR]\z/) &&
              (colon = target.match(/\A(.+?)\s*:\s*(.+)\z/))
          target = colon[1]
          label = colon[2]
        end
        relation = [from, operator, target, label&.strip]
        from = target
        relation
      end
    end

    def useful_line?(line)
      !line.match?(/\A(?:[}\]]\z|(?:accTitle|accDescr|click|style|classDef|class|linkStyle|config|theme|showData|dateFormat|axisFormat|tickInterval|excludes|section|x-axis|y-axis|bar|line|title|end|align|columns|id|text|risk|verifymethod|docref|type|UpdateElementStyle|UpdateRelStyle|UpdateLayoutConfig|AddElementTag|AddRelTag|Lay_(?:U|Up|D|Down|L|Left|R|Right))\b)/i)
    end
  end
end
