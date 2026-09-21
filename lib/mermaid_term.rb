# frozen_string_literal: true

require_relative "mermaid_term/version"
require_relative "mermaid_term/text"
require_relative "mermaid_term/source"
require_relative "mermaid_term/markdown"
require_relative "mermaid_term/scene"
require_relative "mermaid_term/raster"
require_relative "mermaid_term/output"
require_relative "mermaid_term/flowchart"

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
      source = Source.parse(input)
      keyword = source.lines.first.to_s.lstrip[/\A[^\s;]+/]
      plugin = @plugins.find { |candidate| candidate.keywords.include?(keyword) }
      raise UnsupportedDiagramError, "unsupported diagram: #{keyword || '(empty)'}" unless plugin

      ast, findings = plugin.parse(source)
      diagnostics = (source.diagnostics + findings).freeze
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
      plugin.layout(ast, **options)
    end

    def render(**options)
      charset = options.fetch(:charset, :unicode)
      picture = scene(**options)
      grid = Raster.rasterize(picture, charset: charset, rounded: options.fetch(:rounded, true),
                             ambiguous_width: options.fetch(:ambiguous_width, 1))
      Output.render(grid, charset: charset, color: options.fetch(:color, false), theme: options.fetch(:theme, :default))
    end
  end
end

MermaidTerm.register(MermaidTerm::Flowchart)
