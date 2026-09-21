# frozen_string_literal: true

module MermaidTerm
  # One Mermaid fence extracted from a Markdown document.
  MarkdownBlock = Data.define(:source, :line) do
    def render(**options)
      MermaidTerm.render(source, **options)
    end
  end

  module Markdown
    module_function

    def blocks(markdown)
      result = []
      fence = nil
      start = nil
      content = []
      markdown.to_s.each_line.with_index(1) do |line, number|
        if fence
          if line.match?(/\A\s*#{Regexp.escape(fence[0])}{#{fence.length},}\s*\z/)
            result << MarkdownBlock.new(source: content.join, line: start) if start
            fence = nil
            start = nil
            content = []
          else
            content << line if start
          end
        elsif line =~ /\A\s*(`{3,}|~{3,})([^`~]*)\z/
          fence = Regexp.last_match(1)
          start = number + 1 if Regexp.last_match(2).strip == "mermaid"
        end
      end
      result.freeze
    end
  end
end
