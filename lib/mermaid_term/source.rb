# frozen_string_literal: true

require "json"

module MermaidTerm
  # A nonfatal parser finding with original source coordinates.
  Diagnostic = Data.define(:severity, :message, :line, :column, :length) do
    def format(path = "<input>", source = nil)
      header = "#{path}:#{line}:#{column}: #{severity}: #{message}"
      return header unless source && line && source.lines[line - 1]

      line_text = source.lines[line - 1].chomp
      "#{header}\n  #{line} | #{line_text}\n    | #{' ' * [column - 1, 0].max}#{'^' * [length || 1, 1].max}"
    end

    alias to_s format
  end

  # Prepared Mermaid source with original line numbers.
  Source = Data.define(:lines, :title, :directives, :line_map, :original, :diagnostics) do
    def self.parse(input)
      original = input.to_s.scrub.gsub(/\r\n?/, "\n")
      rows = original.lines
      title = nil
      directives = {}
      diagnostics = []
      first = 0
      if rows.first&.chomp == "---"
        closing = (1...rows.length).find { |index| rows[index].chomp == "---" }
        if closing
          rows[1...closing].each_with_index do |line, index|
            if line =~ /\A\s*title:\s*(.*?)\s*\z/
              title = Regexp.last_match(1).delete_prefix('"').delete_suffix('"').delete_prefix("'").delete_suffix("'")
            elsif line.include?(":")
              diagnostics << Diagnostic.new(severity: :info, message: "frontmatter key ignored", line: index + 2, column: 1, length: 1)
            end
          end
          first = closing + 1
        else
          diagnostics << Diagnostic.new(severity: :error, message: "unclosed frontmatter", line: 1, column: 1, length: 3)
          first = rows.length
        end
      end
      lines = []
      line_map = []
      rows.each_with_index do |row, index|
        next if index < first

        stripped = row.strip
        if stripped.start_with?("%%{")
          begin
            payload = stripped.delete_prefix("%%{").delete_suffix("}%%")
            key, body = payload.split(":", 2)
            raise JSON::ParserError unless key == "init" && body && stripped.end_with?("}%%")

            parsed = JSON.parse(body.tr("'", '"'))
            raise JSON::ParserError unless parsed.is_a?(Hash)
            directives.merge!(parsed)
            parsed.each_key { |name| diagnostics << Diagnostic.new(severity: :info, message: "init key #{name} ignored", line: index + 1, column: 1, length: row.length) unless name == "theme" }
          rescue JSON::ParserError
            diagnostics << Diagnostic.new(severity: :warning, message: "invalid init directive", line: index + 1, column: 1, length: row.length)
          end
          next
        end
        next if stripped.empty? || stripped.start_with?("%%")

        lines << row.chomp
        line_map << index + 1
      end
      new(lines: lines.freeze, title: title, directives: directives.freeze, line_map: line_map.freeze,
          original: original.freeze, diagnostics: diagnostics.freeze)
    end
  end

  class Error < StandardError; end
  class SyntaxError < Error; end
  class UnsupportedDiagramError < Error; end
end
