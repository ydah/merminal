# frozen_string_literal: true

require "optparse"

module Merminal
  # Command line interface for files, pipes and Markdown fences.
  module CLI
    module_function

    def run(argv = ARGV, stdin: $stdin, stdout: $stdout, stderr: $stderr)
      options = { charset: :unicode, color: :auto, theme: nil, rounded: true, crossings: :plain,
                  fit: :compact, check: false, strict: false, markdown: false, compact: false }
      parser = OptionParser.new do |p|
        p.banner = "Usage: merminal [options] [FILE ...]"
        p.on("-a", "--ascii", "Use printable ASCII") { options[:charset] = :ascii }
        p.on("-t", "--theme NAME", "Color theme") { |name| options[:theme] = name.to_sym }
        p.on("--list-themes", "List themes") { options[:list_themes] = true }
        p.on("--color WHEN", %w[auto always never], "auto, always or never") { |value| options[:color] = value.to_sym }
        p.on("-w", "--width N", Integer, "Target terminal width") { |value| options[:width] = value }
        p.on("--no-fit", "Disable width fitting") { options[:fit] = nil }
        p.on("--fit MODE", %w[compact rotate], "compact or rotate") { |value| options[:fit] = value.to_sym }
        p.on("--compact", "Use compact spacing") { options[:compact] = true }
        p.on("--sharp", "Use sharp corners") { options[:rounded] = false }
        p.on("--crossings MODE", %w[plain bridge], "Crossing style") { |value| options[:crossings] = value.to_sym }
        p.on("--markdown", "Read Mermaid fences") { options[:markdown] = true }
        p.on("--check", "Check syntax without rendering") { options[:check] = true }
        p.on("--strict", "Fail on parser errors") { options[:strict] = true }
        p.on("-o", "--output FILE", "Write output to file") { |path| options[:output] = path }
        p.on("-v", "--version", "Print version") { stdout.puts VERSION; return 0 }
        p.on("-h", "--help", "Print help") { stdout.puts p; return 0 }
      end
      files = parser.parse(argv)
      if options[:list_themes]
        stdout.puts Output::THEMES.keys
        return 0
      end
      raise OptionParser::InvalidArgument, "width must be positive" if options[:width] && !options[:width].positive?
      raise OptionParser::InvalidArgument, "unknown theme" if options[:theme] && !Output::THEMES.key?(options[:theme])

      parts = []
      error_found = false
      (files.empty? ? ["-"] : files).each do |path|
        input = path == "-" ? stdin.read : File.read(path)
        markdown = options[:markdown] || path.match?(/\.(?:md|markdown)\z/i)
        blocks = markdown ? Merminal.markdown_blocks(input) : [MarkdownBlock.new(source: input, line: 1)]
        blocks.each do |block|
          document = Merminal.parse(block.source)
          document.diagnostics.each do |diagnostic|
            error_found ||= diagnostic.severity == :error
            shifted = diagnostic.with(line: diagnostic.line + block.line - 1)
            stderr.puts shifted.format(path, markdown ? input : block.source)
          end
          next if options[:check]

          parts << fitted_render(document, options, stdout, stderr)
        end
      end
      output = parts.join("\n\n")
      options[:output] ? File.write(options[:output], output + (output.empty? ? "" : "\n")) : stdout.puts(output) unless options[:check]
      error_found && (options[:strict] || options[:check]) ? 1 : 0
    rescue UnsupportedDiagramError => e
      stderr.puts e.message
      3
    rescue OptionParser::ParseError, Errno::ENOENT, Errno::EACCES, IOError, ArgumentError => e
      stderr.puts e.message
      2
    end

    def fitted_render(document, options, stdout, stderr)
      width = options[:width] || (stdout.tty? ? terminal_width : nil)
      rendered = document.render(width: width, fit: options[:fit], compact: options[:compact],
                                 charset: options[:charset], color: options[:color], theme: options[:theme],
                                 rounded: options[:rounded], crossings: options[:crossings])
      if width && rendered.lines.any? { |line| Merminal::Text.width(line.gsub(/\e\[[\d;]*m/, "")) > width }
        actual = rendered.lines.map { |line| Merminal::Text.width(line.gsub(/\e\[[\d;]*m/, "")) }.max
        stderr.puts "diagram width #{actual} exceeds target #{width}"
      end
      rendered
    end

    def terminal_width
      return ENV["COLUMNS"].to_i if ENV["COLUMNS"].to_i.positive?

      begin
        require "io/console"
        width = IO.console&.winsize&.last
        return width if width && width.positive?
      rescue LoadError, Errno::ENOTTY, IOError
        nil
      end
      80
    end
  end
end
