# frozen_string_literal: true

require_relative "mermaid_term/version"
require_relative "mermaid_term/text"
require_relative "mermaid_term/source"
require_relative "mermaid_term/markdown"
require_relative "mermaid_term/scene"
require_relative "mermaid_term/raster"
require_relative "mermaid_term/output"
require_relative "mermaid_term/flowchart"
require_relative "mermaid_term/diagrams/base"
require_relative "mermaid_term/diagrams/pie"
require_relative "mermaid_term/diagrams/timeline"
require_relative "mermaid_term/diagrams/mindmap"
require_relative "mermaid_term/diagrams/xychart"
require_relative "mermaid_term/diagrams/gantt"
require_relative "mermaid_term/diagrams/sequence"
require_relative "mermaid_term/diagrams/structure"

# Pure Ruby terminal renderer for a documented subset of Mermaid.
module MermaidTerm
  @plugins = []

  class << self
    # Register a diagram plugin with keywords, parse and layout methods.
    def register(plugin)
      raise ArgumentError, "duplicate diagram keyword" if (@plugins.flat_map(&:keywords) & plugin.keywords).any?

      @plugins << plugin
    end

    # Return supported diagram type symbols in registration order.
    def diagram_types
      @plugins.map(&:diagram_type)
    end

    # Parse a Mermaid document and collect recoverable diagnostics.
    def parse(input, strict: false)
      source = Ractor.make_shareable(Source.parse(input))
      keyword = source.lines.first.to_s.lstrip[/\A[^\s;]+/]
      plugin = @plugins.find { |candidate| candidate.keywords.include?(keyword) }
      raise UnsupportedDiagramError, "unsupported diagram: #{keyword || '(empty)'}" unless plugin

      ast, findings = plugin.parse(source)
      ast = Ractor.make_shareable(ast)
      diagnostics = Ractor.make_shareable(source.diagnostics + findings)
      raise SyntaxError, diagnostics.select { |d| d.severity == :error }.map(&:message).join("; ") if strict && diagnostics.any? { |d| d.severity == :error }

      Document.new(type: plugin.diagram_type, ast: ast, diagnostics: diagnostics, source: source, plugin: plugin)
    end

    # Render Mermaid text to Unicode or ASCII terminal text.
    def render(input, **options)
      strict = options.delete(:strict) || false
      parse(input, strict: strict).render(**options)
    end

    # Extract Mermaid fences from Markdown in source order.
    def markdown_blocks(markdown)
      Markdown.blocks(markdown)
    end
  end

  # Parsed document; the Scene can be rendered with different options.
  Document = Data.define(:type, :ast, :diagnostics, :source, :plugin) do
    def scene(**options)
      picture = plugin.layout(ast, **options)
      return Ractor.make_shareable(picture) unless source.title

      title = Scene::Text.new(x: 0, y: 0, string: source.title, role: :emphasis, layer: :label, emphasis: nil)
      Ractor.make_shareable(Scene.new(width: [picture.width, Text.width(source.title)].max, height: picture.height + 1,
                                       items: ([title] + picture.items.map { |item| Scene.translate(item, dy: 1) }).freeze))
    end

    def render(width: nil, fit: :compact, compact: false, **options)
      unless width && fit
        preset = compact ? { node_gap: 1, rank_gap: 1, node_padding_x: 1, max_label_width: 12 } : {}
        return render_once(**options, **preset)
      end

      raise ArgumentError, "width must be positive" unless width.positive?

      presets = [
        {}, { node_gap: 1, rank_gap: 1 }, { node_gap: 1, rank_gap: 1, node_padding_x: 1 },
        { node_gap: 1, rank_gap: 1, node_padding_x: 1, max_label_width: 16 },
        { node_gap: 1, rank_gap: 1, node_padding_x: 1, max_label_width: 12 }
      ]
      presets = [presets.last] if compact
      presets << presets.last.merge(direction: :TB) if fit == :rotate && type == :flowchart && ast.direction == :LR
      rendered = nil
      presets.each do |preset|
        rendered = render_once(**options, **preset)
        break if rendered.lines.all? { |line| Text.width(line.gsub(/\e\[[\d;]*m/, "")) <= width }
      end
      rendered
    end

    def render_once(**options)
      charset = options.fetch(:charset, :unicode)
      picture = scene(**options)
      grid = Raster.rasterize(picture, charset: charset, rounded: options.fetch(:rounded, true),
                             ambiguous_width: options.fetch(:ambiguous_width, 1), crossings: options.fetch(:crossings, :plain))
      theme = options[:theme] || source.directives.fetch("theme", :default)
      theme = :default unless theme.respond_to?(:to_sym) && Output::THEMES.key?(theme.to_sym)
      Output.render(grid, charset: charset, color: options.fetch(:color, false), theme: theme)
    end
  end
end

MermaidTerm.register(MermaidTerm::Flowchart)
[
  MermaidTerm::Diagrams::Sequence, MermaidTerm::Diagrams::State, MermaidTerm::Diagrams::ClassDiagram,
  MermaidTerm::Diagrams::ER, MermaidTerm::Diagrams::Pie, MermaidTerm::Diagrams::XYChart,
  MermaidTerm::Diagrams::Gantt, MermaidTerm::Diagrams::Timeline, MermaidTerm::Diagrams::Mindmap
].each { |plugin| MermaidTerm.register(plugin) }
