# frozen_string_literal: true

module Merminal::Diagrams::Additional::Specialized
  Scene = Merminal::Scene
  Text = Merminal::Text
  Builder = Merminal::Diagrams::Builder
  Flowchart = Merminal::Flowchart

  module_function

  def scene(ast, **options)
    case ast.keyword
    when "journey" then journey(ast)
    when "quadrantChart" then quadrant(ast)
    when "requirementDiagram" then requirement(ast)
    when "usecaseDiagram", "usecase-beta" then usecase(ast, **options)
    when "gitGraph" then git_graph(ast, **options)
    when /^C4/ then c4(ast, **options)
    when "zenuml" then zenuml(ast)
    when "sankey-beta" then sankey(ast, **options)
    when "block-beta" then block(ast)
    when "packet-beta" then packet(ast)
    when "kanban" then kanban(ast)
    when "architecture-beta" then architecture(ast, **options)
    when "radar-beta" then radar(ast)
    when "treemap-beta" then treemap(ast)
    when "venn-beta" then venn(ast)
    when "ishikawa-beta" then ishikawa(ast)
    when "wardley-beta" then wardley(ast)
    when "treeView", "treeView-beta" then tree_view(ast)
    when "cynefin-beta" then cynefin(ast)
    when "swimlane-beta" then swimlane(ast, **options)
    when "eventModeling" then event_modeling(ast)
    when "agentflow-beta" then agentflow(ast, **options)
    when "railroad-ebnf-beta", "railroad-abnf-beta", "railroad-peg-beta", "railroad-beta" then railroad(ast)
    end
  end

  def railroad(ast)
    rules = railroad_rules(ast)
    builder = Builder.new
    builder.text(0, 0, railroad_title(ast), role: :emphasis)
    y = 2
    rules.each do |name, expression|
      branches = railroad_choices(expression)
      branches = [expression] if branches.empty?
      builder.text(0, y, name, role: :container_title)
      branches.each_with_index do |branch, index|
        row_y = y + 2 + index * 5
        builder.marker(0, row_y + 1, kind: :circle, direction: :e)
        x = 2
        railroad_tokens(branch).each do |token, terminal|
          label = Text.truncate(token, 18)
          width = [Text.width(label) + 4, 6].max
          builder.line([[x - 1, row_y + 1], [x, row_y + 1]])
          builder.box(x, row_y, width, 3, rounded: terminal)
          builder.text(x + 2, row_y + 1, label)
          x += width + 1
        end
        builder.line([[x - 1, row_y + 1], [x, row_y + 1]])
        builder.marker(x, row_y + 1, direction: :e)
      end
      y += [branches.length, 1].max * 5 + 3
    end
    builder.text(0, y, "No grammar rules", role: :container_title) if rules.empty?
    builder.scene
  end

  def railroad_title(ast)
    ast.title.to_s.delete_prefix('"').delete_suffix('"').delete_prefix("'").delete_suffix("'").then do |title|
      title.empty? ? "Railroad Diagram" : title
    end
  end

  def railroad_rules(ast)
    railroad_statements(ast.lines).filter_map do |statement|
      match = statement.match(/\A\s*([A-Za-z_][\w-]*)\s*(::=|=|<-)\s*(.+?)\s*\z/m)
      [match[1], match[3]] if match
    end
  end

  def railroad_statements(lines)
    statements = []
    current = +""
    quote = nil
    comment = nil
    depth = 0
    lines.each do |line|
      text = line.strip
      next if text.empty? || text.match?(/\A(?:title|accTitle|accDescr)\b/i)

      current << " " unless current.empty?
      index = 0
      while index < text.length
        if comment
          if text[index, comment.length] == comment
            index += comment.length
            comment = nil
          else
            index += 1
          end
          next
        end

        if quote.nil? && ["/*", "(*"].include?(text[index, 2])
          comment = text[index, 2] == "/*" ? "*/" : "*)"
          index += 2
          next
        end

        char = text[index]
        break if quote.nil? && char == "#"

        if quote
          quote = nil if quote == char
        elsif ['"', "'"].include?(char)
          quote = char
        elsif "([{".include?(char)
          depth += 1
        elsif ")]}".include?(char) && depth.positive?
          depth -= 1
        end
        current << char
        if char == ";" && quote.nil? && depth.zero?
          statements << current.delete_suffix(";").strip
          current = +""
          break
        end
        index += 1
      end
    end
    statements << current.strip unless current.strip.empty?
    statements
  end

  def railroad_choices(expression)
    if (match = expression.match(/\Achoice\s*\((.*)\)\z/m))
      return railroad_split(match[1], [","])
    end

    choices = []
    current = +""
    quote = nil
    depth = 0
    expression.each_char do |char|
      if quote
        quote = nil if quote == char
      elsif ['"', "'"].include?(char)
        quote = char
      elsif "([{".include?(char)
        depth += 1
      elsif ")]}".include?(char) && depth.positive?
        depth -= 1
      end
      if quote.nil? && depth.zero? && ["|", "/"].include?(char)
        choices << current.strip
        current = +""
      else
        current << char
      end
    end
    choices << current.strip unless current.strip.empty?
    choices.length > 1 ? choices : []
  end

  def railroad_split(expression, separators)
    parts = []
    current = +""
    quote = nil
    depth = 0
    expression.each_char do |char|
      if quote
        quote = nil if quote == char
      elsif ['"', "'"].include?(char)
        quote = char
      elsif "([{".include?(char)
        depth += 1
      elsif ")]}".include?(char) && depth.positive?
        depth -= 1
      end
      if quote.nil? && depth.zero? && separators.include?(char)
        parts << current.strip
        current = +""
      else
        current << char
      end
    end
    parts << current.strip unless current.strip.empty?
    parts
  end

  def railroad_tokens(expression)
    tokens = []
    scanner = StringScanner.new(expression)
    until scanner.eos?
      scanner.skip(/\s+|,/)
      break if scanner.eos?

      next if scanner.scan(%r{/\*.*?\*/|\(\*.*?\*\)|#.*\z/m})

      if (match = scanner.scan(/(?:terminal|nonterminal|special)\s*\(\s*(["'])(.*?)\1\s*\)/))
        value = match[/["']((?:\\.|[^"'])*)["']/, 1]
        tokens << [value, !match.start_with?("nonterminal")]
      elsif (match = scanner.scan(/["']((?:\\.|[^"'])*)["']/))
        tokens << [match[/["']((?:\\.|[^"'])*)["']/, 1], true]
      elsif (match = scanner.scan(/%[xbd][0-9A-Fa-f.\-]+|[.!&]/))
        tokens << [match, true]
      elsif (match = scanner.scan(/\?([^?\n]+)\?/))
        tokens << [match[/\?([^?\n]+)\?/, 1].strip, true]
      elsif (match = scanner.scan(/[A-Za-z_][\w-]*/))
        tokens << [match, false] unless %w[sequence choice optional zeroOrMore oneOrMore].include?(match)
      elsif scanner.peek(1) && "?*+|/()[]{}-".include?(scanner.peek(1))
        marker = scanner.getch
        if %w[? * +].include?(marker) && tokens.last
          tokens[-1][0] = "#{tokens.last[0]}#{marker}"
        elsif marker == "-"
          tokens << [marker, true]
        elsif %w[? * +].include?(marker)
          tokens << [marker, false]
        end
      else
        scanner.getch
      end
    end
    tokens
  end

  def journey(ast)
    sections = []
    section = "Journey"
    ast.lines.each do |line|
      if line =~ /\A\s*section\s+(.+)\z/i
        section = Regexp.last_match(1).strip
        sections << [section, []]
      elsif line =~ /\A\s*(.+?):\s*(\d+)(?::\s*(.*))?\z/
        sections << [section, []] if sections.empty? || sections.last.first != section
        sections.last.last << [Regexp.last_match(1).strip, Regexp.last_match(2).to_i, Regexp.last_match(3).to_s.strip]
      end
    end
    width = [sections.flat_map { |_, rows| rows }.map { |name, _, actors| Text.width("#{name} #{actors}") }.max.to_i + 18, 44].max
    builder = Builder.new
    y = 0
    builder.text(0, y, ast.title || "User Journey", role: :emphasis)
    y += 2
    sections.each do |name, rows|
      builder.box(0, y, width, 3, role: :container_border)
      builder.text(2, y + 1, name, role: :container_title)
      y += 4
      rows.each do |label, score, actors|
        builder.box(0, y, width, 3)
        bar = "#" * [[score, 5].min, 0].max + "." * [5 - score, 0].max
        builder.text(2, y + 1, "#{Text.pad(Text.truncate(label, 18), 18)} #{bar} #{actors}")
        y += 4
      end
    end
    builder.scene
  end

  def quadrant(ast)
    x_labels = ast.lines.find { |line| line =~ /\Ax-axis\s+/i }.to_s.sub(/\Ax-axis\s+/i, "").split(/\s+-->\s+/)
    y_labels = ast.lines.find { |line| line =~ /\Ay-axis\s+/i }.to_s.sub(/\Ay-axis\s+/i, "").split(/\s+-->\s+/)
    quadrants = ast.lines.filter_map do |line|
      match = line.match(/\A\s*quadrant-([1-4])\s+(.+)\z/i)
      [match[1].to_i, match[2].strip] if match
    end
    points = ast.lines.filter_map do |line|
      match = line.match(/\A\s*([^:]+):\s*\[\s*([\d.]+)\s*,\s*([\d.]+)\s*\]/)
      [match[1].strip, match[2].to_f, match[3].to_f] if match
    end
    left, top, width, height = 8, 3, 48, 16
    builder = Builder.new
    builder.text(0, 0, ast.title || "Quadrant Chart", role: :emphasis)
    builder.box(left, top, width, height)
    builder.line([[left + width / 2, top], [left + width / 2, top + height - 1]])
    builder.line([[left, top + height / 2], [left + width - 1, top + height / 2]])
    builder.text(left, top + height, x_labels.first.to_s)
    builder.text(left + width - Text.width(x_labels.last.to_s), top + height, x_labels.last.to_s)
    builder.text(0, top + height - 1, y_labels.first.to_s)
    builder.text(0, top, y_labels.last.to_s)
    quadrant_positions = {
      1 => [left + width / 2 + 2, top + 1],
      2 => [left + 2, top + 1],
      3 => [left + 2, top + height / 2 + 1],
      4 => [left + width / 2 + 2, top + height / 2 + 1]
    }
    quadrants.each { |number, label| builder.text(*quadrant_positions.fetch(number), label) }
    points.each do |label, x, y|
      px = left + 1 + (x.clamp(0, 1) * (width - 3)).round
      py = top + height - 2 - (y.clamp(0, 1) * (height - 3)).round
      builder.glyph(px, py, "o")
      builder.text(px + 2, py, label)
    end
    builder.scene
  end

  def requirement(ast)
    requirements = []
    current = nil
    ast.lines.each do |line|
      if line =~ /\A\s*(requirement|functionalRequirement|interfaceRequirement|performanceRequirement|physicalRequirement|designConstraint|element)\s+([^\s{]+)/i
        current = { kind: Regexp.last_match(1), id: Regexp.last_match(2), values: {} }
        requirements << current
      elsif current && line =~ /\A\s*(id|text|risk|verifymethod|docref|type):\s*(.+)\z/i
        current[:values][Regexp.last_match(1).downcase] = Regexp.last_match(2).strip
      elsif line.strip == "}"
        current = nil
      end
    end
    return if requirements.empty?

    relation_width = ast.edges.map { |edge| Text.width("#{edge.from} --#{edge.label || "relates"}--> #{edge.to}") }.max.to_i
    detail_width = requirements.map do |item|
      values = item[:values]
      Text.width("risk: #{values["risk"] || "-"}  verify: #{values["verifymethod"] || "-"}  type: #{values["type"]}  doc: #{values["docref"]}")
    end.max.to_i
    width = [requirements.map { |item| Text.width(item[:values]["text"].to_s) }.max.to_i + 24, detail_width + 4, relation_width + 4, 44].max
    builder = Builder.new
    builder.text(0, 0, ast.title || "Requirements", role: :emphasis)
    y = 2
    requirements.each do |item|
      builder.box(0, y, width, 5, rounded: true)
      values = item[:values]
      builder.text(2, y + 1, "#{item[:kind]} #{item[:id]}", role: :container_title)
      builder.text(2, y + 2, values["text"].to_s)
      details = "risk: #{values["risk"] || "-"}  verify: #{values["verifymethod"] || "-"}"
      details += "  type: #{values["type"]}" if values["type"]
      details += "  doc: #{values["docref"]}" if values["docref"]
      builder.text(2, y + 3, details)
      y += 6
    end
    unless ast.edges.empty?
      builder.text(0, y, "Relations", role: :container_title)
      y += 2
      ast.edges.each do |edge|
        builder.text(2, y, "#{edge.from} --#{edge.label || "relates"}--> #{edge.to}")
        y += 2
      end
    end
    builder.scene
  end

  def usecase(ast, **options)
    return if ast.nodes.empty?

    declarations = {}
    actors = []
    ast.lines.each do |line|
      if (match = line.match(/\A\s*(?:actor|person)\s+([\w-]+)(?:\s+as\s+(.+))?/i))
        id = match[1]
        actors << id
        declarations[id] = [match[2].to_s.strip.delete_prefix('"').delete_suffix('"').then { |label| label.empty? ? id : label }, :circle]
      elsif (match = line.match(/\A\s*(?:usecase\s+)?["']([^"']+)["']\s+as\s+([\w-]+)/i))
        declarations[match[2]] = [match[1], :stadium]
      elsif (match = line.match(/\A\s*usecase\s+([\w-]+)(?:\s+as\s+(.+))?/i))
        declarations[match[1]] = [match[2].to_s.strip.delete_prefix('"').delete_suffix('"').then { |label| label.empty? ? match[1] : label }, :stadium]
      end
    end
    ast.lines.each do |line|
      if (match = line.match(/\A\s*([\w-]+)\s*\[([^\]]+)\]/))
        declarations[match[1]] = [match[2].strip.delete_prefix('"').delete_suffix('"'), :rectangle]
      elsif (match = line.match(/\A\s*([\w-]+)\s*\(([^)]+)\)/))
        declarations[match[1]] = [match[2].strip.delete_prefix('"').delete_suffix('"'), :stadium]
      elsif (match = line.match(/\A\s*\(([^)]+)\)/))
        id = match[1].gsub(/\W+/, "_")
        declarations[id] = [match[1].strip.delete_prefix('"').delete_suffix('"'), :stadium]
      end
    end
    boundaries = []
    stack = []
    ast.lines.each do |line|
      if (match = line.match(/\A\s*(?:systemBoundary|rectangle)\s+([^\s\[{]+)(?:\[([^\]]+)\]|\(([^)]+)\))?\s*\{/i))
        boundary = [match[1], (match[2] || match[3]).to_s.strip.then { |label| label.empty? ? match[1] : label }, []]
        boundaries << boundary
        stack << boundary
      elsif line.strip == "}"
        stack.pop
      elsif stack.any?
        declarations.keys.each { |id| stack.last[2] << id if line.match?(Regexp.new("\\b#{Regexp.escape(id)}\\b")) }
      end
    end
    boundary_ids = boundaries.map(&:first)
    inferred = ast.nodes.reject { |node| node.id.start_with?("line") || node.id == "title" || boundary_ids.include?(node.id) }.map(&:id)
    known_ids = (inferred + actors + declarations.keys + ast.edges.flat_map { |edge| [edge.from, edge.to] }).uniq - boundary_ids
    return if known_ids.empty?

    nodes = known_ids.map do |id|
      original = ast.nodes.find { |node| node.id == id }
      label, shape = declarations.fetch(id, [original&.label || id, actors.include?(id) ? :circle : :stadium])
      Flowchart::Node.new(id: id, label: label, shape: actors.include?(id) ? :circle : shape, classes: [].freeze, source_pos: [1, 1])
    end
    subgraphs = boundaries.map { |id, label, members| Flowchart::Subgraph.new(id: id, label: label, node_ids: members.uniq.freeze, parent: nil) }
    edges = ast.edges.select { |edge| known_ids.include?(edge.from) && known_ids.include?(edge.to) }.each_with_index.map do |edge, index|
      Flowchart::Edge.new(id: index, from: edge.from, to: edge.to, label: edge.label, stroke: :light, start_marker: nil, end_marker: :arrow, minlen: 1, source_pos: [1, 1])
    end
    flow_scene(nodes, edges, direction: ast.direction, subgraphs: subgraphs, **options)
  end

  def git_graph(ast, **options)
    commits = []
    branches = { "main" => nil }
    current = "main"
    attributes = lambda do |line|
      [line[/\bid\s*:\s*["']?([^"'\s]+)["']?/i, 1],
       line[/\btype\s*:\s*([A-Za-z]+)/i, 1].to_s.upcase,
       line[/\btag\s*:\s*["']?([^"']+)["']?/i, 1]]
    end
    ast.lines.each do |line|
      if line =~ /\A\s*commit\b/i
        custom_id, type, tag = attributes.call(line)
        id = custom_id || "c#{commits.length + 1}"
        commits << [id, current, branches[current], nil, type, tag]
        branches[current] = id
      elsif line =~ /\A\s*branch\s+([^\s]+)/i
        name = Regexp.last_match(1).delete_prefix('"').delete_suffix('"')
        branches[name] = branches[current]
      elsif line =~ /\A\s*(?:checkout|switch)\s+([^\s]+)/i
        current = Regexp.last_match(1).delete_prefix('"').delete_suffix('"')
        branches[current] ||= branches["main"]
      elsif line =~ /\A\s*cherry-pick\b/i
        source = line[/\bid\s*:\s*["']?([^"'\s]+)["']?/i, 1]
        next unless source && commits.any? { |commit| commit[0] == source }

        custom_id, type, tag = attributes.call(line)
        id = custom_id || "c#{commits.length + 1}"
        commits << [id, current, branches[current], source, type, tag]
        branches[current] = id
      elsif line =~ /\A\s*merge\s+([^\s]+)/i
        source = branches[Regexp.last_match(1).delete_prefix('"').delete_suffix('"')]
        custom_id, type, tag = attributes.call(line)
        id = custom_id || "c#{commits.length + 1}"
        commits << [id, current, branches[current], source, type, tag]
        branches[current] = id
      end
    end
    nodes = commits.map do |id, branch, _parent, _merge, type, tag|
      shape = type == "REVERSE" ? :cross : type == "HIGHLIGHT" ? :rectangle : :circle
      label = [id, branch, tag].compact.reject(&:empty?).join(" ")
      Flowchart::Node.new(id: id, label: label, shape: shape, classes: [].freeze, source_pos: [1, 1])
    end
    edges = []
    commits.each do |id, _branch, parent, merge, _type, _tag|
      edges << Flowchart::Edge.new(id: edges.length, from: parent, to: id, label: nil, stroke: :light, start_marker: nil, end_marker: :arrow, minlen: 1, source_pos: [1, 1]) if parent
      edges << Flowchart::Edge.new(id: edges.length, from: merge, to: id, label: "merge", stroke: :dotted, start_marker: nil, end_marker: :arrow, minlen: 1, source_pos: [1, 1]) if merge
    end
    return if nodes.empty?

    flow = Flowchart::Diagram.new(direction: ast.direction, nodes: nodes.freeze, edges: edges.freeze, subgraphs: [].freeze, styles: {}.freeze)
    Flowchart.layout(flow, **options)
  end

  def c4(ast, **options)
    return if ast.nodes.empty?

    boundaries = []
    stack = []
    ast.lines.each do |line|
      if (match = line.match(/\A\s*((?:Enterprise_)?Boundary|System_Boundary|Container_Boundary|Component_Boundary)\(([^,]+),\s*["']?([^"')]+)["']?\)\s*\{/i))
        boundary = [match[2].strip, match[3].strip, [], stack.last&.first]
        boundaries << boundary
        stack << boundary
      elsif line.strip == "}"
        stack.pop
      elsif stack.any?
        ast.nodes.each { |node| stack.last[2] << node.id if line.match?(Regexp.new("\\b#{Regexp.escape(node.id)}\\b")) }
      end
    end
    boundary_ids = boundaries.map(&:first)
    nodes = ast.nodes.reject { |node| boundary_ids.include?(node.id) }.map do |node|
      type = ast.lines.find { |line| line =~ /\A\s*([A-Za-z_]+)\(#{Regexp.escape(node.id)}[,\s]/ }&.match(/\A\s*([A-Za-z_]+)/)&.[](1).to_s
      shape = if type =~ /Person/ || type == "Node" then :circle
              elsif type =~ /Db/ then :database
              elsif type =~ /Queue/ then :stadium
              else :rectangle end
      Flowchart::Node.new(id: node.id, label: node.label, shape: shape, classes: [].freeze, source_pos: [1, 1])
    end
    node_ids = nodes.map(&:id)
    subgraphs = boundaries.map { |id, label, members, parent| Flowchart::Subgraph.new(id: id, label: label, node_ids: members.uniq.freeze, parent: parent) }
    edges = ast.edges.select { |edge| node_ids.include?(edge.from) && node_ids.include?(edge.to) }.each_with_index.map do |edge, index|
      Flowchart::Edge.new(id: index, from: edge.from, to: edge.to, label: edge.label, stroke: :light, start_marker: nil, end_marker: :arrow, minlen: 1, source_pos: [1, 1])
    end
    flow_scene(nodes, edges, direction: ast.direction, subgraphs: subgraphs, **options)
  end

  def zenuml(ast)
    participants = []
    messages = []
    aliases = {}
    ast.lines.each do |line|
      if line =~ /\A\s*title\b/i || line.match?(/\A\s*\/\//)
        next
      elsif (match = line.match(/\A\s*}\s*(else(?:\s+if)?|catch|finally)(?:\s*\(([^)]*)\))?\s*\{\s*\z/i))
        condition = match[2].to_s
        messages << [nil, nil, "end", :fragment]
        messages << [nil, nil, "#{match[1]}#{condition.empty? ? "" : "(#{condition})"}", :fragment]
      elsif (match = line.match(/\A\s*(while|for|forEach|foreach|loop|if|else(?:\s+if)?|opt|par|try|catch|finally|break)(?:\s*\(([^)]*)\))?\s*\{\s*\z/i))
        condition = match[2].to_s
        messages << [nil, nil, "#{match[1]}#{condition.empty? ? "" : "(#{condition})"}", :fragment]
      elsif line.match?(/\A\s*}\s*\z/)
        messages << [nil, nil, "end", :fragment]
      elsif line =~ /\A\s*([\w.-]+)\s+as\s+["']?(.+?)["']?\s*\z/i
        aliases[Regexp.last_match(1)] = Regexp.last_match(2).strip
      elsif line =~ /\A\s*([\w.-]+)\s*(?:->|-->|<-|<--)\s*([\w.-]+)(?:\s*:\s*(.*))?\z/
        from, to, text = Regexp.last_match.captures
        from, to = [to, from] if line.include?("<-")
        participants |= [from, to]
        messages << [from, to, text.to_s.strip]
      elsif line =~ /\A\s*([\w.-]+)\.([\w.-]+)(?:\(([^)]*)\))?\s*\z/
        participant, method, arguments = Regexp.last_match.captures
        participants << participant
        suffix = arguments.nil? ? "" : "(#{arguments})"
        messages << [participant, participant, "#{method}#{suffix}"]
      elsif line =~ /\A\s*(?:@\w+\s+|new\s+)?([\w.-]+)\s*\z/i
        participants << Regexp.last_match(1)
      end
    end
    participants = participants.map { |participant| aliases.fetch(participant, participant) }
    messages = messages.map { |from, to, text| [aliases.fetch(from, from), aliases.fetch(to, to), text] }
    sequence_scene(participants, messages, ast.title || "ZenUML")
  end

  def sankey(ast, **options)
    flows = ast.lines.filter_map do |line|
      fields = csv_fields(line)
      next unless fields&.length == 3 && fields[2].to_s.match?(/\A\s*\d+(?:\.\d+)?\s*\z/)

      [fields[0].strip, fields[1].strip, fields[2].strip]
    end
    return if flows.empty?

    nodes = flows.flat_map { |from, to,| [from, to] }.uniq.map { |id| Flowchart::Node.new(id: id, label: id, shape: :rectangle, classes: [].freeze, source_pos: [1, 1]) }
    edges = flows.each_with_index.map { |(from, to, amount), index| Flowchart::Edge.new(id: index, from: from, to: to, label: amount, stroke: :heavy, start_marker: nil, end_marker: :arrow, minlen: 1, source_pos: [1, 1]) }
    flow = Flowchart::Diagram.new(direction: :LR, nodes: nodes.freeze, edges: edges.freeze, subgraphs: [].freeze, styles: {}.freeze)
    Flowchart.layout(flow, **options)
  end

  def csv_fields(line)
    fields = []
    field = +""
    quoted = false
    index = 0
    while index < line.length
      char = line[index]
      if quoted
        if char == '"' && line[index + 1] == '"'
          field << '"'
          index += 1
        elsif char == '"'
          quoted = false
        else
          field << char
        end
      elsif char == '"' && field.empty?
        quoted = true
      elsif char == ","
        fields << field.strip
        field = +""
      else
        field << char
      end
      index += 1
    end
    fields << field.strip
    fields
  end

  def block(ast)
    columns = ast.lines.find { |line| line =~ /\A\s*columns\s+(\d+)/i }&.match(/(\d+)/)&.[](1).to_i
    columns = 3 if columns.zero?
    links = ast.lines.filter_map do |line|
      match = line.match(/\A\s*([\w-]+)\s*(?:-->|---)\s*([\w-]+)/)
      [match[1], match[2]] if match
    end
    cells = ast.lines.reject { |line| line =~ /\A\s*(?:columns\b|[\w-]+\s*(?:-->|---)\s*[\w-]+)/i }
                     .reject { |line| line.strip.casecmp("end").zero? }
                     .flat_map { |line| block_cells(line) }
                     .each_slice(columns).to_a.reject(&:empty?)
    cells << links.map { |from, to| "#{from} -> #{to}" } unless links.empty?
    grid_scene(ast.title || "Block Diagram", cells)
  end

  def block_cells(line)
    tokens = []
    token = +""
    depth = 0
    quote = nil
    line.each_char do |char|
      if quote
        quote = nil if char == quote
      elsif ['"', "'"].include?(char)
        quote = char
      elsif "[({<".include?(char)
        depth += 1
      elsif "])}>".include?(char)
        depth -= 1 if depth.positive?
      elsif char.match?(/\s/) && depth.zero?
        tokens << token unless token.empty?
        token = +""
        next
      end
      token << char
    end
    tokens << token unless token.empty?
    tokens.flat_map do |cell|
      if (space = cell.match(/\Aspace(?::(\d+))?\z/i))
        Array.new([space[1].to_i, 1].max, "")
      elsif (span = cell.match(/\A([\w-]+):(\d+)\z/))
        [block_label(span[1])] + Array.new([span[2].to_i, 1].max - 1, "")
      else
        [block_label(cell)]
      end
    end
  end

  def block_label(cell)
    label = cell[/\[\"?([^\]"]+)\"?\]/, 1] || cell[/\(\"?([^\)"]+)\"?\)/, 1]
    label ||= cell[/<\[\"?([^\]"]*)\"?\]/, 1]
    return label unless label.to_s.empty?

    cell.sub(/\Ablock:/i, "").sub(/:([0-9]+)\z/, "")
  end

  def packet(ast)
    bit = 0
    fields = ast.lines.filter_map do |line|
      match = line.match(/\A\s*(\+?\d+(?:-\d+)?)\s*:\s*["']?(.+?)["']?\s*(?:%%.*)?\z/)
      next unless match

      range = match[1]
      start_bit, end_bit = if range.start_with?("+")
                             [bit, bit + range.delete_prefix("+").to_i - 1]
                           elsif range.include?("-")
                             range.split("-", 2).map(&:to_i)
                           else
                             value = range.to_i
                             [value, value]
                           end
      bit = end_bit + 1
      [start_bit, end_bit, match[2].strip]
    end
    fields = [[0, 0, "packet"]] if fields.empty?
    builder = Builder.new
    builder.text(0, 0, ast.title || "Packet", role: :emphasis)
    total = [fields.map { |_start_bit, end_bit,| end_bit }.max.to_i + 1, 1].max
    scale = [48.0 / total, 2.0].max
    x = 0
    fields.each do |start_bit, end_bit, label|
      width = [[((end_bit - start_bit + 1) * scale).round, 4].max, 48 - x].min
      builder.box(x, 3, width, 5)
      builder.text(x + 1, 5, Text.truncate(label, width - 2))
      builder.text(x + 1, 4, Text.truncate("#{start_bit}-#{end_bit}", width - 2))
      x += width
    end
    builder.scene
  end

  def kanban(ast)
    columns = []
    current = nil
    entries = ast.lines.reject { |line| line.strip.empty? }
    base_indent = entries.map { |line| line[/\A\s*/].to_s.length }.min || 0
    ast.lines.each do |line|
      indent = line[/\A\s*/].to_s.length
      content = line.strip
      relative_indent = indent - base_indent
      if relative_indent.zero? && content =~ /\A(?:([^\s\[]+)\s*)?\[([^\]]+)\]/
        current = { name: Regexp.last_match(2), tasks: [] }
        columns << current
      elsif relative_indent.zero? && content =~ /\A([^\s\[]+)\s*\z/
        current = { name: Regexp.last_match(1), tasks: [] }
        columns << current
      elsif current && relative_indent.positive? && (match = content.match(/\A(?:[^\s\[]+\s*)?\[([^\]]+)\](?:@\{\s*(.+?)\s*\})?/))
        label = match[1]
        label += " {#{match[2]}}" if match[2]
        current[:tasks] << label
      end
    end
    columns = [{ name: "Board", tasks: ast.nodes.map(&:label) }] if columns.empty?
    width = columns.map { |column| [Text.width(column[:name]), column[:tasks].map { |task| Text.width(task) }.max.to_i].max + 4 }.max
    builder = Builder.new
    columns.each_with_index do |column, index|
      x = index * (width + 2)
      height = [column[:tasks].length * 4 + 3, 3].max
      builder.box(x, 0, width, height, role: :container_border)
      builder.text(x + 2, 1, column[:name], role: :container_title)
      column[:tasks].each_with_index do |task, row|
        builder.box(x + 1, 3 + row * 4, width - 2, 3, rounded: true)
        builder.text(x + 2, 4 + row * 4, task)
      end
    end
    builder.scene
  end

  def architecture(ast, **options)
    groups = []
    services = []
    ast.lines.each do |line|
      if line =~ /\A\s*group\s+([\w-]+)(?:\(([^)]*)\))?(?:\[([^\]]+)\])?(?:\s+in\s+([\w-]+))?/i
        groups << [Regexp.last_match(1), Regexp.last_match(3).to_s.empty? ? Regexp.last_match(1) : Regexp.last_match(3), [], Regexp.last_match(4)]
      elsif line =~ /\A\s*service\s+([\w-]+)(?:\(([^)]*)\))?(?:\[([^\]]+)\])?(?:\s+in\s+([\w-]+))?/i
        services << [Regexp.last_match(1), Regexp.last_match(2).to_s, Regexp.last_match(3).to_s.empty? ? Regexp.last_match(1) : Regexp.last_match(3), Regexp.last_match(4)]
      elsif line =~ /\A\s*junction\s+([\w-]+)/i
        services << [Regexp.last_match(1), "", Regexp.last_match(1), nil]
      end
    end
    return usecase(ast, **options) if services.empty?

    known_ids = services.map(&:first)
    ast.edges.each { |edge| known_ids |= [edge.from, edge.to] }
    service_nodes = services + known_ids.reject { |id| services.any? { |service| service[0] == id } }.map { |id| [id, "", id, nil] }
    nodes = service_nodes.map do |id, icon, label,|
      shape = icon == "database" ? :database : icon == "cloud" ? :stadium : :rectangle
      Flowchart::Node.new(id: id, label: label, shape: shape, classes: [].freeze, source_pos: [1, 1])
    end
    groups.each { |id, _label, members, _parent| members.concat(service_nodes.filter_map { |service| service[0] if service[3] == id }) }
    subgraphs = groups.map { |id, label, members, parent| Flowchart::Subgraph.new(id: id, label: label, node_ids: members.freeze, parent: parent) }
    flow = Flowchart::Diagram.new(direction: ast.direction, nodes: nodes.freeze,
                                  edges: ast.edges.each_with_index.map { |edge, index| Flowchart::Edge.new(id: index, from: edge.from, to: edge.to, label: edge.label, stroke: :light, start_marker: nil, end_marker: :arrow, minlen: 1, source_pos: [1, 1]) }.freeze,
                                  subgraphs: subgraphs.freeze, styles: {}.freeze)
    Flowchart.layout(flow, **options)
  end

  def radar(ast)
    axis_lines = ast.lines.select { |line| line =~ /\A\s*axis\b/i }
    axes = axis_lines.flat_map { |line| line.sub(/\A\s*axis\s+/i, "").split(/\s*,\s*/) }.filter_map do |token|
      match = token.match(/\A\s*([\w-]+)\s*\[\s*["']?([^\]"]+)["']?\s*\]\s*\z/)
      next [match[1], match[2].strip] if match

      label = token.strip.delete_prefix('"').delete_suffix('"')
      [label, label] unless label.empty?
    end
    axes = %w[A B C D].map { |axis| [axis, axis] } if axes.empty?
    curves = ast.lines.flat_map do |line|
      line.scan(/([\w-]+)(?:\s*\[\s*["']?([^\]"]+)["']?\s*\])?\s*\{([^}]+)\}/i).map do |name, label, body|
        values = body.split(/\s*,\s*/).filter_map do |part|
          key, value = part.split(/\s*:\s*/, 2)
          value ? [key.strip, value.to_f] : part.to_f
        end
        [name, label.to_s.strip, values]
      end
    end
    max_value = ast.lines.find { |line| line =~ /\A\s*max\s+[-+]?\d+(?:\.\d+)?/i }&.match(/[-+]?\d+(?:\.\d+)?/)&.[](0)&.to_f
    min_value = ast.lines.find { |line| line =~ /\A\s*min\s+[-+]?\d+(?:\.\d+)?/i }&.match(/[-+]?\d+(?:\.\d+)?/)&.[](0)&.to_f || 0
    observed = curves.flat_map { |_, _, values| values.map { |value| value.is_a?(Array) ? value[1] : value } }
    max_value ||= [observed.max.to_f, min_value + 1].max
    range = [max_value - min_value, 1].max
    radius = 8
    cx = radius + 2
    cy = radius + 2
    builder = Builder.new
    builder.text(0, 0, ast.title || "Radar", role: :emphasis)
    axes.each_with_index do |(_id, label), index|
      angle = (Math::PI * 2 * index / axes.length) - Math::PI / 2
      ex = cx + (Math.cos(angle) * radius).round
      ey = cy + (Math.sin(angle) * radius).round
      builder.line([[cx, cy], [ex, cy], [ex, ey]])
      builder.text(ex, ey, label)
    end
    curves.each_with_index do |(name, label, values), curve_index|
      points = axes.each_index.map do |index|
        value = if values.any? { |item| item.is_a?(Array) }
                  values.find { |axis,| axis == axes[index][0] }&.last.to_f
                else
                  values.fetch(index, 0).to_f
                end
        value = (value - min_value) / range
        angle = (Math::PI * 2 * index / axes.length) - Math::PI / 2
        [cx + (Math.cos(angle) * radius * value).round, cy + (Math.sin(angle) * radius * value).round]
      end
      points.each_with_index do |point, index|
        next_point = points[(index + 1) % points.length]
        builder.line([[point[0], point[1]], [next_point[0], point[1]], [next_point[0], next_point[1]]])
      end
      builder.text(cx + radius + 4, cy + curve_index * 2 - 2, label.empty? ? name : label)
    end
    builder.glyph(cx, cy, "o") if curves.empty?
    builder.scene
  end

  def treemap(ast)
    nodes = []
    stack = []
    ast.lines.each do |line|
      next if line.strip.empty? || line.match?(/\A\s*(?:classDef|style)\b/i)

      value_match = line.match(/\s*:\s*(\d+(?:\.\d+)?)\s*\z/)
      value = value_match && value_match[1].to_f
      label = value_match ? line[0...value_match.begin(0)] : line
      label = label.sub(/\s*:::[\w-]+\s*\z/, "").strip
      label = label.delete_prefix('"').delete_suffix('"').delete_prefix("'").delete_suffix("'")
      next if label.empty?

      depth = line[/\A\s*/].to_s.gsub("\t", "  ").length / 2
      node = { depth: depth, label: label, value: value, children: [] }
      stack.pop while stack.any? && stack.last[:depth] >= depth
      stack.last[:children] << node if stack.any?
      stack << node
      nodes << node
    end
    nodes = [{ depth: 0, label: "Root", value: 1.0, children: [] }] if nodes.empty?
    total_value = lambda do |node|
      node[:size] = node[:value] || node[:children].sum { |child| total_value.call(child) }
      node[:size] = 1.0 if node[:size].zero?
      node[:size]
    end
    nodes.select { |node| node[:depth].zero? }.each { |node| total_value.call(node) }
    builder = Builder.new
    builder.text(0, 0, ast.title || "Treemap", role: :emphasis)
    nodes.group_by { |node| node[:depth] }.sort.each do |depth, row|
      total = [row.sum { |node| node[:size] || total_value.call(node) }, 1].max
      x = depth * 3
      row.each do |node|
        width = [[(48 * node[:size] / total).round, Text.width(node[:label]) + 4].max, 10].max
        y = 2 + depth * 5
        builder.box(x, y, width, 4, role: depth.zero? ? :container_border : :node_border)
        builder.text(x + 2, y + 1, node[:label])
        size = node[:size]
        builder.text(x + 2, y + 2, size.to_i == size ? size.to_i.to_s : size.to_s)
        x += width + 1
      end
    end
    builder.scene
  end

  def venn(ast)
    sets = []
    unions = []
    text_nodes = []
    ast.lines.each do |line|
      if (match = line.match(/\A\s*set\s+(?:"([^"]+)"|([^\s\[:]+))(?:\[\s*"?([^\]"]+)"?\s*\])?(?:\s*:\s*(\d+(?:\.\d+)?))?\s*\z/i))
        id = match[1] || match[2]
        sets << [id, match[3].to_s.empty? ? id : match[3], match[4]&.to_f]
      elsif line.match?(/\A\s*union\s+/i)
        body = line.sub(/\A\s*union\s+/i, "").strip
        value = body[/:\s*(\d+(?:\.\d+)?)\s*\z/, 1]&.to_f
        body = body.sub(/:\s*\d+(?:\.\d+)?\s*\z/, "")
        label = body[/\[\s*["']?([^\]"']+)["']?\s*\]\z/, 1]
        members = body.sub(/\[[^\]]+\]\s*\z/, "").split(/\s*[&,]\s*/).map { |member| member.delete_prefix('"').delete_suffix('"') }
        unions << [members, label || members.join("&"), value]
      elsif line.match?(/\A\s*text\s+/i)
        body = line.sub(/\A\s*text\s+/i, "").strip
        if (match = body.match(/\A([^\s\[]+)\s*\[\s*["']?([^\]"']+)["']?\s*\]\s*\z/))
          text_nodes << [match[1], match[2]]
        elsif (match = body.match(/\A([^:]+):\s*["']?(.+?)["']?\s*\z/))
          text_nodes << [match[1].strip, match[2].strip]
        end
      end
    end
    sets = [["A", "A", 1.0], ["B", "B", 1.0]] if sets.empty?
    builder = Builder.new
    builder.text(0, 0, ast.title || "Venn Diagram", role: :emphasis)
    positions = []
    x = 0
    label_x = 0
    sets.each do |_id, label, value|
      width = [Text.width(label) + 6, 24].max
      positions << [x, width]
      builder.box(x, 3, width, 8, rounded: true)
      builder.text(label_x, 1, label)
      builder.text(label_x, 2, value.to_s) if value
      x += [width / 2, 10].max
      label_x += width + 2
    end
    unions.each_with_index do |(_members, union_label, value), index|
      label = union_label
      label += ": #{value}" if value
      center = positions.sum { |position, width| position + width / 2 } / [positions.length, 1].max
      builder.text([center - Text.width(label) / 2, 0].max, 12 + index, label)
    end
    text_nodes.each_with_index do |(target, label), index|
      builder.text(0, 14 + index, "#{target}: #{label}")
    end
    builder.scene
  end

  def ishikawa(ast)
    problem = ast.lines.find { |line| !line.strip.empty? }&.strip || "Problem"
    causes = ast.lines.drop(1).filter_map do |line|
      next if line.strip.empty?

      indent = line[/\A\s*/].to_s.gsub("\t", "  ").length / 2
      [indent, line.strip]
    end
    builder = Builder.new
    builder.text(0, 0, ast.title || "Ishikawa", role: :emphasis)
    y = [causes.length + 3, 6].max
    builder.line([[0, y], [42, y]])
    builder.text(43, y - 1, problem, role: :emphasis)
    causes.each_with_index do |(indent, cause), index|
      x = 4 + index * 8
      branch_y = y - 3 - indent
      builder.line([[x, y], [x, branch_y], [x + 5 + indent * 2, branch_y]])
      builder.text(x + indent * 2, branch_y - 1, cause)
    end
    builder.scene
  end

  def wardley(ast)
    points = ast.lines.filter_map do |line|
      match = line.match(/\A\s*(?:anchor|component)\s+(.+?)\s*\[\s*(\d+(?:\.\d+)?)\s*,\s*(\d+(?:\.\d+)?)\s*\]/i)
      next unless match

      [match[1].strip.delete_prefix('"').delete_suffix('"'), match[2].to_f, match[3].to_f]
    end
    evolutions = ast.lines.filter_map do |line|
      match = line.match(/\A\s*evolve\s+(.+?)\s+(\d+(?:\.\d+)?)\s*\z/i)
      [match[1].strip.delete_prefix('"').delete_suffix('"'), match[2].to_f] if match
    end.to_h
    points = points.map { |label, visibility, evolution| [label, visibility, evolutions.fetch(label, evolution)] }
    links = ast.lines.filter_map do |line|
      match = line.match(/\A\s*(.+?)\s+\+['"](.+?)['"]>\s+(.+?)\s*\z/)
      next [match[1].strip.delete_prefix('"').delete_suffix('"'), match[3].strip.delete_prefix('"').delete_suffix('"'), match[2]] if match

      match = line.match(/\A\s*(.+?)\s+(?:-->|->|\+>|<\+|\+<|\+<>|-\.->)\s+(.+?)(?:\s*;\s*(.+?))?\s*\z/)
      [match[1].strip.delete_prefix('"').delete_suffix('"'), match[2].strip.delete_prefix('"').delete_suffix('"'), match[3]&.strip] if match
    end
    trends = ast.lines.filter_map do |line|
      match = line.match(/\A\s*(.+?)\s+-\.\-\s*\[?\(?\s*(\d+(?:\.\d+)?)\s*,\s*(\d+(?:\.\d+)?)\s*\]?\)?\s*\z/)
      [match[1].strip.delete_prefix('"').delete_suffix('"'), match[2].to_f, match[3].to_f] if match
    end
    notes = ast.lines.filter_map do |line|
      match = line.match(/\A\s*note\s+["'](.+?)["']\s*\[\s*(\d+(?:\.\d+)?)\s*,\s*(\d+(?:\.\d+)?)\s*\]\s*\z/i)
      [match[1], match[2].to_f, match[3].to_f] if match
    end
    annotations = ast.lines.filter_map do |line|
      match = line.match(/\A\s*annotation\s+(\d+)\s*,\s*\[\s*(\d+(?:\.\d+)?)\s*,\s*(\d+(?:\.\d+)?)\s*\]\s+["'](.+?)["']\s*\z/i)
      [match[1], match[2].to_f, match[3].to_f, match[4]] if match
    end
    decorators = ast.lines.filter_map do |line|
      match = line.match(/\A\s*(?:anchor|component)\s+(.+?)\s*\[\s*\d+(?:\.\d+)?\s*,\s*\d+(?:\.\d+)?\s*\]\s*\((inertia|build|buy|outsource|market)\)\s*\z/i)
      [match[1].strip.delete_prefix('"').delete_suffix('"'), match[2].downcase] if match
    end.to_h
    pipelines = []
    pipeline_stack = []
    ast.lines.each do |line|
      if (match = line.match(/\A\s*pipeline\s+(.+?)\s*\{\s*\z/i))
        pipeline = [match[1].strip.delete_prefix('"').delete_suffix('"'), []]
        pipelines << pipeline
        pipeline_stack << pipeline
      elsif line.strip == "}"
        pipeline_stack.pop unless pipeline_stack.empty?
      elsif pipeline_stack.any? && (match = line.match(/\A\s*(?:anchor|component)\s+(.+?)\s*\[/i))
        pipeline_stack.last[1] << match[1].strip.delete_prefix('"').delete_suffix('"')
      end
    end
    evolution_stages = ast.lines.filter_map do |line|
      match = line.match(/\A\s*evolution\s+(.+?)\s*\z/i)
      match[1].split(/\s*->\s*/).map(&:strip) if match
    end
    builder = Builder.new
    builder.text(0, 0, ast.title || "Wardley Map", role: :emphasis)
    builder.line([[5, 3], [5, 19]])
    builder.line([[5, 19], [55, 19]])
    coordinates = points.to_h { |label, visibility, evolution| [label, [5 + (evolution.clamp(0, 1) * 48).round, 19 - (visibility.clamp(0, 1) * 14).round]] }
    links.each do |from, to, label|
      a = coordinates[from]
      b = coordinates[to]
      next unless a && b

      builder.line([a, [b[0], a[1]], b])
      builder.text((a[0] + b[0]) / 2, [a[1], b[1]].min - 1, label) if label
    end
    points.each do |label, visibility, evolution|
      px = 5 + (evolution.clamp(0, 1) * 48).round
      py = 19 - (visibility.clamp(0, 1) * 14).round
      builder.glyph(px, py, "o")
      builder.text(px + 2, py, label)
    end
    decorators.each do |label, decorator|
      point = coordinates[label]
      next unless point

      builder.text(point[0] + 2, point[1] + 1, "(#{decorator})", role: :muted)
    end
    trends.each do |label, evolution, visibility|
      point = coordinates[label]
      next unless point

      target = [5 + (evolution.clamp(0, 1) * 48).round, 19 - (visibility.clamp(0, 1) * 14).round]
      builder.line([point, [target[0], point[1]], target])
      builder.text(target[0] + 1, target[1], "trend")
    end
    notes.each do |text, visibility, evolution|
      px = 5 + (evolution.clamp(0, 1) * 48).round
      py = 19 - (visibility.clamp(0, 1) * 14).round
      builder.text(px, py + 1, "note: #{text}", role: :container_title)
    end
    annotations.each do |number, x, y, text|
      px = 5 + (x.clamp(0, 1) * 48).round
      py = 19 - (y.clamp(0, 1) * 14).round
      builder.text(px, py, "#{number}: #{text}", role: :container_title)
    end
    y = 22
    unless pipelines.empty?
      builder.text(0, y, "Pipelines", role: :container_title)
      pipelines.each do |name, members|
        label = "#{name}: #{members.join(' -> ')}"
        builder.box(0, y + 1, [Text.width(label) + 4, 24].max, 3, role: :container_border)
        builder.text(2, y + 2, label)
        y += 4
      end
    end
    evolution_stages.each do |stages|
      label = "Evolution: #{stages.join(' -> ')}"
      builder.text(0, y, label, role: :container_title)
      y += 2
    end
    builder.scene
  end

  def tree_view(ast)
    tree_scene(ast.title || "TreeView", ast.lines)
  end

  def cynefin(ast)
    names = %w[clear complicated complex chaotic confusion]
    domains = names.to_h { |name| [name, []] }
    current = nil
    transitions = []
    ast.lines.each do |line|
      if (match = line.match(/\A\s*(#{names.join("|")})\s*\z/i))
        current = match[1].downcase
      elsif (match = line.match(/\A\s*(#{names.join("|")})\s*-->\s*(#{names.join("|")})(?:\s*:\s*["']?(.+?)["']?)?\s*\z/i))
        transitions << [match[1].downcase, match[2].downcase, match[3].to_s.strip]
        current = nil
      elsif current && line.strip != "" && !line.match?(/\Atitle\b/i)
        domains[current] << line.strip.delete_prefix('"').delete_suffix('"')
      end
    end
    domains = { "clear" => ["Sense", "Categorise", "Respond"], "complicated" => ["Sense", "Analyse", "Respond"],
                "complex" => ["Probe", "Sense", "Respond"], "chaotic" => ["Act", "Sense", "Respond"], "confusion" => [] } if domains.values.all?(&:empty?)
    builder = Builder.new
    builder.text(0, 0, ast.title || "Cynefin", role: :emphasis)
    labels = { "clear" => "Clear", "complicated" => "Complicated", "complex" => "Complex", "chaotic" => "Chaotic", "confusion" => "Confusion" }
    %w[complex complicated chaotic clear].each_with_index do |domain, index|
      x = index % 2 * 30
      y = 2 + index / 2 * 9
      height = [domains[domain].length * 2 + 4, 7].max
      builder.box(x, y, 28, height, role: :container_border)
      builder.text(x + 2, y + 1, labels[domain], role: :container_title)
      domains[domain].each_with_index { |item, row| builder.text(x + 2, y + 3 + row * 2, item) }
    end
    builder.box(15, 20, 28, [domains["confusion"].length * 2 + 4, 5].max, rounded: true)
    builder.text(17, 21, labels["confusion"], role: :container_title)
    domains["confusion"].each_with_index { |item, row| builder.text(17, 23 + row * 2, item) }
    transitions.each_with_index { |(from, to, label), index| builder.text(0, 27 + index * 2, "#{labels[from]} -> #{labels[to]} #{label}") }
    builder.scene
  end

  def swimlane(ast, **options)
    lanes = []
    current = nil
    ast.lines.each do |line|
      if (match = line.match(/\A\s*subgraph\s+([^\[]+)(?:\[([^\]]+)\])?/i))
        current = [match[1].strip, match[2].to_s.strip, []]
        lanes << current
      elsif line.strip.casecmp("end").zero?
        current = nil
      elsif current
        ast.nodes.each { |node| current[2] << node.id if line.match?(Regexp.new("\\b#{Regexp.escape(node.id)}\\b")) }
      end
    end
    return if lanes.empty?

    member_ids = lanes.flat_map { |_, _, members| members }.uniq
    nodes = ast.nodes.select { |node| member_ids.include?(node.id) }.map do |node|
      Flowchart::Node.new(id: node.id, label: node.label, shape: :rectangle, classes: [].freeze, source_pos: [1, 1])
    end
    subgraphs = lanes.map { |id, label, members| Flowchart::Subgraph.new(id: id, label: label.empty? ? id : label, node_ids: members.uniq.freeze, parent: nil) }
    flow = Flowchart::Diagram.new(direction: ast.direction, nodes: nodes.freeze,
                                  edges: ast.edges.each_with_index.map { |edge, index| Flowchart::Edge.new(id: index, from: edge.from, to: edge.to, label: edge.label, stroke: :light, start_marker: nil, end_marker: :arrow, minlen: 1, source_pos: [1, 1]) }.freeze,
                                  subgraphs: subgraphs.freeze, styles: {}.freeze)
    Flowchart.layout(flow, **options)
  end

  def event_modeling(ast)
    relations = []
    frames = ast.lines.filter_map do |line|
      match = line.match(/\A\s*(tf|timeframe|rf|resetframe)\s+(\S+)\s+(\S+)\s+(.+)\z/i)
      next unless match

      label = match[4].strip.delete_prefix('"').delete_suffix('"')
      inline_data = label[/\s+\{.*\}\s*\z/m]
      label = label.delete_suffix(inline_data.to_s).strip
      parts = label.split(/\s+->>\s+/).map(&:strip)
      if parts.length > 1
        parts.each_cons(2) { |from, to| relations << [from, to] }
        label = parts.first
      end
      type = case match[3].downcase
             when "ui", "processor", "pcr" then "pcr"
             when "command", "cmd", "readmodel", "rmo" then "cmd"
             when "event", "evt" then "evt"
             else match[3].downcase
             end
      label = "#{label}#{inline_data}" if inline_data
      namespace = label.split(/[.]/, 2).first if label.include?(".")
      lane = namespace ? "#{type}:#{namespace}" : type
      [match[2], lane, label, %w[rf resetframe].include?(match[1].downcase)]
    end
    return tree_scene(ast.title || "Event Modeling", ast.lines) if frames.empty?

    data_blocks = []
    current_data = nil
    ast.lines.each do |line|
      if (match = line.match(/\A\s*data\s+(\S+)(?:\s+`[^`]+`)?\s*\{(.*)\z/i))
        current_data = { name: match[1], fields: [] }
        data_blocks << current_data
        inline = match[2].to_s.strip
        current_data[:fields] << inline unless inline.empty? || inline == "}"
        current_data = nil if line.include?("}")
      elsif current_data
        content = line.strip
        closing = content.end_with?("}")
        content = content.delete_suffix("}").strip if closing
        current_data[:fields] << content unless content.empty?
        current_data = nil if closing
      end
    end
    lanes = frames.map { |_, type,| type }.uniq
    gap = [frames.map { |number, _, label, reset| Text.width("#{reset ? "rf " : ""}#{number} #{label}") + 7 }.max.to_i, 14].max
    lane_width = [14 + (frames.length - 1) * gap + gap, 24].max
    builder = Builder.new
    builder.text(0, 0, ast.title || "Event Modeling", role: :emphasis)
    lanes.each_with_index do |lane, lane_index|
      y = 2 + lane_index * 5
      builder.box(0, y, lane_width, 4, role: :container_border)
      builder.text(2, y + 1, lane, role: :container_title)
    end
    frames.each_with_index do |(number, type, label, reset), index|
      lane_index = lanes.index(type)
      x = 14 + index * gap
      y = 2 + lane_index * 5
      display = "#{reset ? "rf " : ""}#{number} #{label}"
      builder.box(x, y, [Text.width(display) + 5, 10].max, 4, rounded: true)
      builder.text(x + 2, y + 1, display)
      builder.line([[x - 2, y + 2], [x, y + 2]]) if index.positive?
    end
    y = 2 + lanes.length * 5
    unless relations.empty?
      builder.text(0, y, "Relations", role: :container_title)
      relations.each_with_index { |(from, to), index| builder.text(2, y + 1 + index * 2, "#{from} ->> #{to}") }
      y += relations.length * 2 + 2
    end
    unless data_blocks.empty?
      builder.text(0, y, "Data", role: :container_title)
      data_blocks.each do |name|
        row = y + 1
        fields = name[:fields]
        lines = [name[:name], *fields]
        width = [lines.map { |line| Text.width(line) }.max.to_i + 4, 10].max
        height = [lines.length + 2, 3].max
        builder.box(0, row, width, height, rounded: true)
        lines.each_with_index { |line, line_index| builder.text(2, row + 1 + line_index, line) }
        y = row + height + 1
      end
    end
    builder.scene
  end

  def agentflow(ast, **options)
    flows = []
    stack = []
    shapes = {}
    ast.lines.each do |line|
      if (match = line.match(/\A\s*flow\s+([\w-]+)\s*\[\"?([^\]"}]+)\"?\]/i))
        flow = [match[1], match[2].strip, []]
        flows << flow
        stack << flow
      elsif line.strip.casecmp("end").zero?
        stack.pop
      else
        ast.nodes.each do |node|
          next unless line.match?(Regexp.new("\\b#{Regexp.escape(node.id)}\\b"))

          stack.last[2] << node.id if stack.any?
          if (match = line.match(/\b#{Regexp.escape(node.id)}\b[^@]*@\{\s*shape:\s*([\w-]+)/i))
            shapes[node.id] = { "input" => :parallelogram, "task" => :rectangle, "decision" => :decision,
                                "start" => :stadium, "end" => :stadium }.fetch(match[1].downcase, :rectangle)
          end
        end
      end
    end
    nodes = ast.nodes.reject { |node| flows.any? { |id, _,| id == node.id } }.map do |node|
      label = node.label.delete_prefix('"').delete_suffix('"')
      Flowchart::Node.new(id: node.id, label: label, shape: shapes.fetch(node.id, :rectangle), classes: [].freeze, source_pos: [1, 1])
    end
    subgraphs = flows.map { |id, label, members| Flowchart::Subgraph.new(id: id, label: label, node_ids: members.uniq.freeze, parent: nil) }
    edges = ast.edges.each_with_index.map { |edge, index| Flowchart::Edge.new(id: index, from: edge.from, to: edge.to, label: edge.label, stroke: :light, start_marker: nil, end_marker: :arrow, minlen: 1, source_pos: [1, 1]) }
    if nodes.empty? && edges.empty?
      rows = flows.map { |id, label,| [label.empty? ? id : label] }
      return grid_scene(ast.title || "AgentFlow", rows) unless rows.empty?
    end

    flow_scene(nodes, edges, direction: ast.direction, subgraphs: subgraphs, **options)
  end

  def flow_scene(nodes, edges, direction:, subgraphs: [], **options)
    node_ids = nodes.map(&:id)
    edges = edges.select { |edge| node_ids.include?(edge.from) && node_ids.include?(edge.to) }
    flow = Flowchart::Diagram.new(direction: direction, nodes: nodes.freeze, edges: edges.freeze,
                                  subgraphs: subgraphs.freeze, styles: {}.freeze)
    Flowchart.layout(flow, **options)
  end

  def sequence_scene(participants, messages, title)
    participants = ["Actor"] if participants.empty?
    builder = Builder.new
    gap = 14
    builder.text(0, 0, title, role: :emphasis)
    participants.each_with_index do |participant, index|
      x = index * gap
      builder.box(x, 2, [Text.width(participant) + 4, 9].max, 3, rounded: true)
      builder.text(x + 2, 3, participant)
      builder.line([[x + 3, 5], [x + 3, 5 + [messages.length, 1].max * 3]])
    end
    messages.each_with_index do |(from, to, text, kind), index|
      y = 6 + index * 3
      if kind == :fragment
        builder.text(1, y - 1, text, role: :container_title)
        next
      end
      x1 = participants.index(from).to_i * gap + 3
      x2 = participants.index(to).to_i * gap + 3
      builder.line([[x1, y], [x2, y]])
      builder.marker(x2, y, direction: x2 >= x1 ? :e : :w)
      builder.text([x1, x2].min + 1, y - 1, text)
    end
    builder.scene
  end

  def grid_scene(title, rows)
    rows = [["block"]] if rows.empty?
    width = rows.flatten.reject(&:empty?).map { |cell| Text.width(cell) }.max.to_i + 4
    builder = Builder.new
    builder.text(0, 0, title, role: :emphasis)
    rows.each_with_index do |row, y|
      row.each_with_index do |cell, x|
        next if cell.empty?

        builder.box(x * width, 2 + y * 4, width, 3)
        builder.text(x * width + 2, 3 + y * 4, cell)
      end
    end
    builder.scene
  end

  def tree_scene(title, lines)
    builder = Builder.new
    builder.text(0, 0, title, role: :emphasis)
    lines = ["root"] if lines.empty?
    lines.each_with_index do |line, index|
      branch = line.match(/[\u251c\u2514\u2523\u2517]/)
      if branch
        indent = Text.width(line[0...branch.begin(0)]) / 4 + 1
        label = line.sub(/.*?[\u251c\u2514\u2523\u2517][\u2500\u2501]+/, "").strip
      else
        indent = line[/\A\s*/].to_s.length / 2
        label = line.strip
      end
      description = label[/\s*##\s*(.+)\z/, 1]
      label = label.sub(/\s*##\s*.+\z/, "").sub(/\s*:::[\w-]+\s*\z/, "").strip
      label = label.delete_prefix('"').delete_suffix('"').delete_prefix("'").delete_suffix("'")
      label += " (#{description})" if description
      x = indent * 4
      y = 2 + index * 2
      if indent.positive?
        builder.line([[x - 3, y], [x, y]])
        builder.line([[x - 3, y - 1], [x - 3, y]])
      end
      builder.text(x + (indent.positive? ? 1 : 0), y, label, role: label.end_with?("/") ? :emphasis : :node_text)
    end
    builder.scene
  end
end
