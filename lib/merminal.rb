# frozen_string_literal: true

require_relative "merminal/version"
require_relative "merminal/shareable"
require_relative "merminal/text"
require_relative "merminal/source"
require_relative "merminal/markdown"
require_relative "merminal/scene"
require_relative "merminal/raster"
require_relative "merminal/output"
require_relative "merminal/flowchart"
require_relative "merminal/diagrams/base"
require_relative "merminal/diagrams/pie"
require_relative "merminal/diagrams/timeline"
require_relative "merminal/diagrams/mindmap"
require_relative "merminal/diagrams/xychart"
require_relative "merminal/diagrams/gantt"
require_relative "merminal/diagrams/sequence"
require_relative "merminal/diagrams/structure"
require_relative "merminal/diagrams/additional"
require_relative "merminal/diagrams/additional_layouts"

# Pure Ruby terminal renderer for a documented subset of Mermaid.
module Merminal
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
      source = Shareable.make(Source.parse(input))
      keyword = source.lines.first.to_s.lstrip[/\A[^\s;]+/]
      plugin = @plugins.find { |candidate| candidate.keywords.include?(keyword) }
      raise UnsupportedDiagramError, "unsupported diagram: #{keyword || '(empty)'}" unless plugin

      ast, findings = plugin.parse(source)
      ast = Shareable.make(ast)
      diagnostics = Shareable.make(source.diagnostics + findings)
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
      return Shareable.make(picture) unless source.title

      title = Scene::Text.new(x: 0, y: 0, string: source.title, role: :emphasis, layer: :label, emphasis: nil)
      Shareable.make(Scene.new(width: [picture.width, Text.width(source.title)].max, height: picture.height + 1,
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

Merminal.register(Merminal::Flowchart)
[
  Merminal::Diagrams::Sequence, Merminal::Diagrams::State, Merminal::Diagrams::ClassDiagram,
  Merminal::Diagrams::ER, Merminal::Diagrams::Pie, Merminal::Diagrams::XYChart,
  Merminal::Diagrams::Gantt, Merminal::Diagrams::Timeline, Merminal::Diagrams::Mindmap
].each { |plugin| Merminal.register(plugin) }
Merminal::Diagrams::Additional::KEYWORDS.each do |keyword|
  aliases = Merminal::Diagrams::Additional::ALIASES.fetch(keyword, [keyword])
  Merminal.register(Merminal::Diagrams::Additional.plugin(keyword, aliases: aliases))
end
