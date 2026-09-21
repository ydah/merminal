# frozen_string_literal: true

require "strscan"
require "cgi"

module MermaidTerm
  # Flowchart grammar and Scene layout.
  module Flowchart
    Node = Data.define(:id, :label, :shape, :classes, :source_pos)
    Edge = Data.define(:id, :from, :to, :label, :stroke, :start_marker, :end_marker, :minlen, :source_pos)
    Subgraph = Data.define(:id, :label, :node_ids, :parent)
    Diagram = Data.define(:direction, :nodes, :edges, :subgraphs, :styles)

    SHAPES = [
      ["(((", ")))", :double_circle], ["((", "))", :circle], ["([", "])", :stadium],
      ["[(", ")]", :database], ["[[", "]]", :subroutine], ["{{", "}}", :hexagon],
      ["(", ")", :rounded], ["{", "}", :decision], ["[", "]", :rectangle], [">", "]", :flag]
    ].freeze
    EDGE_PATTERN = /(?:<|o|x)?(?:-{2,}|-\.+-|={2,}|~{3,})(?:>|o|x)?/
    DIRECTIONS = %w[TB TD BT LR RL].freeze

    def self.diagram_type = :flowchart
    def self.keywords = %w[flowchart graph]

    def self.parse(source)
      Parser.new(source).parse
    end

    def self.layout(ast, **options)
      Layout.new(ast, **options).scene
    end

    # Statement parser; scanner offsets are used in diagnostics.
    class Parser
      def initialize(source)
        @source = source
        @nodes = {}
        @edges = []
        @subgraphs = []
        @styles = {}
        @diagnostics = []
        @stack = []
        @direction = :TB
      end

      def parse
        header, *rest = @source.lines
        header_parts = header.to_s.split(";", 2)
        words = header_parts[0].to_s.split
        @direction = words[1].to_sym if DIRECTIONS.include?(words[1])
        split_statements(header_parts[1].to_s).each { |statement| parse_statement(statement.strip, @source.line_map.first || 1) } if header_parts[1]
        rest.each_with_index do |line, index|
          split_statements(line.to_s).each { |statement| parse_statement(statement.strip, @source.line_map[index + 1] || 1) }
        end
        @subgraphs.each do |group|
          representative = group.node_ids.first
          next unless representative

          @edges.map! do |edge|
            edge.with(from: edge.from == group.id ? representative : edge.from,
                      to: edge.to == group.id ? representative : edge.to)
          end
          @nodes.delete(group.id) unless group.node_ids.include?(group.id)
        end
        @diagnostics << Diagnostic.new(severity: :error, message: "unclosed subgraph", line: @source.line_map.last || 1, column: 1, length: 1) unless @stack.empty?
        [Diagram.new(direction: @direction, nodes: @nodes.values.freeze, edges: @edges.freeze,
                     subgraphs: @subgraphs.freeze, styles: @styles.freeze), @diagnostics.freeze]
      end

      def split_statements(line)
        statements = []
        current = +""
        quote = nil
        depth = 0
        line.each_char do |char|
          if quote
            quote = nil if char == quote
          elsif char == '"' || char == "'"
            quote = char
          elsif ["(", "[", "{"].include?(char)
            depth += 1
          elsif [")", "]", "}"].include?(char)
            depth -= 1 if depth.positive?
          elsif char == ";" && depth.zero?
            statements << current
            current = +""
            next
          end
          current << char
        end
        statements << current
      end

      def parse_statement(statement, line)
        return if statement.empty?

        case statement
        when /\Adirection\s+(TB|TD|BT|LR|RL)\z/
          if @stack.any?
            info("subgraph direction ignored", line)
          else
            @direction = Regexp.last_match(1).to_sym
          end
        when /\Asubgraph\s+(.+)\z/
          name = Regexp.last_match(1).strip
          id, label = name =~ /\A([^\[]+)\[(.*)\]\z/ ? [Regexp.last_match(1).strip, Regexp.last_match(2)] : [name, name]
          @subgraphs << Subgraph.new(id: id, label: label, node_ids: [], parent: @stack.last)
          @stack << id
        when "end"
          @stack.pop || error("unexpected end", line)
        when /\Astyle\s+(\S+)\s+(.+)\z/
          @styles[Regexp.last_match(1)] = Regexp.last_match(2)
        when /\AclassDef\s+(\S+)\s+(.+)\z/
          @styles["class:#{Regexp.last_match(1)}"] = Regexp.last_match(2)
        when /\Aclass\s+([\w,.-]+)\s+(\S+)\z/
          ids, name = Regexp.last_match.captures
          ids.split(",").each do |id|
            previous = @nodes[id]
            @nodes[id] = previous.with(classes: (previous.classes + [name]).uniq.freeze) if previous
          end
        when /\AlinkStyle\s+(\S+)\s+(.+)\z/
          @styles["link:#{Regexp.last_match(1)}"] = Regexp.last_match(2)
        when /\Aclick\b/
          info("click ignored", line)
        else
          parse_chain(statement, line)
        end
      end

      def parse_chain(statement, line)
        scanner = StringScanner.new(statement)
        previous = parse_group(scanner, line)
        return unless previous

        until scanner.eos?
          scanner.skip(/\s*/)
          operator = scanner.scan(EDGE_PATTERN)
          unless operator
            error("unexpected input", line, scanner.pos + 1)
            break
          end
          label = nil
          scanner.skip(/\s*/)
          if scanner.scan(/\|/)
            label = scanner.scan_until(/\|/)&.chop
            error("unclosed edge label", line, scanner.pos + 1) unless label
          elsif operator == "--" && scanner.scan(/(.+?)\s+-->/)
            label = scanner[1]
            operator = "-->"
          end
          following = parse_group(scanner, line)
          break unless following

          previous.product(following).each do |from, to|
            @edges << Edge.new(id: @edges.length, from: from, to: to, label: label,
                               stroke: operator.include?("~") ? :invisible : operator.include?("=") ? :heavy : operator.include?(".") ? :dotted : :light,
                               start_marker: marker(operator[0]), end_marker: marker(operator[-1]),
                               minlen: [operator.count("-=.") - 1, 1].max, source_pos: [line, scanner.pos])
          end
          previous = following
        end
      end

      def parse_group(scanner, line)
        ids = []
        loop do
          scanner.skip(/\s*/)
          id = scanner.scan(/[[:alnum:]_](?:[[:alnum:]_.]|-(?![-.=>~]))*/)
          unless id
            error("expected node", line, scanner.pos + 1)
            return nil
          end
          shape, label = parse_shape(scanner, line)
          previous = @nodes[id]
          classes = []
          while scanner.scan(/:::/)
            name = scanner.scan(/[[:alnum:]_-]+/)
            classes << name if name
          end
          label ||= previous&.label || id
          label = CGI.unescapeHTML(label.gsub(/<br\s*\/?\s*>/i, "\n").gsub(/<[^>]+>/, ""))
          if previous && shape
            info("node #{id} redefined", line)
          end
          @nodes[id] = Node.new(id: id, label: shape ? label : previous&.label || label,
                                shape: shape || previous&.shape || :rectangle,
                                classes: ((previous&.classes || []) + classes).uniq.freeze, source_pos: [line, scanner.pos])
          @subgraphs.each { |group| group.node_ids << id if @stack.include?(group.id) } if @stack.any?
          ids << id
          scanner.skip(/\s*/)
          break unless scanner.scan(/&/)
        end
        ids
      end

      def parse_shape(scanner, line)
        if scanner.scan(/@\{/)
          value = scanner.scan_until(/\}/)
          unless value
            error("unclosed shape object", line, scanner.pos + 1)
            return [:rectangle, ""]
          end
          name = value[/shape\s*:\s*([\w-]+)/, 1]
          shape = { "rect" => :rectangle, "rounded" => :rounded, "diamond" => :decision,
                    "hex" => :hexagon, "circle" => :circle, "stadium" => :stadium,
                    "cyl" => :database, "subproc" => :subroutine }[name]
          info("unknown shape #{name}", line) unless shape
          return [shape || :rectangle, nil]
        end
        if scanner.peek(2) == "[/" || scanner.peek(2) == "[\\"
          value = scanner.scan_until(/\]/)
          unless value
            error("unclosed node shape", line, scanner.pos + 1)
            return [:parallelogram, ""]
          end
          first = value[1]
          last = value[-2]
          shape = first == last ? :parallelogram : :trapezoid
          return [shape, value[2...-2]]
        end
        opener, closer, shape = SHAPES.find { |start, _, _| scanner.peek(start.length) == start }
        return [nil, nil] unless opener

        scanner.pos += opener.length
        value = scanner.scan_until(Regexp.new(Regexp.escape(closer)))
        unless value
          error("unclosed node shape", line, scanner.pos + 1)
          return [shape, ""]
        end
        [shape, value.delete_suffix(closer).delete_prefix('"').delete_suffix('"')]
      end

      def marker(char)
        { ">" => :arrow, "<" => :arrow, "o" => :circle, "x" => :cross }[char]
      end

      def error(message, line, column = 1)
        @diagnostics << Diagnostic.new(severity: :error, message: message, line: line, column: column, length: 1)
      end

      def info(message, line)
        @diagnostics << Diagnostic.new(severity: :info, message: message, line: line, column: 1, length: 1)
      end
    end
  end
end

require_relative "flowchart/layout"
