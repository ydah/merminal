# frozen_string_literal: true

require "cgi"
require_relative "../lib/mermaid_term"

def themed_html(grid, theme)
  colors = MermaidTerm::Output::THEMES.fetch(theme)
  rows = grid.lines.map do |cells|
    last = cells.rindex { |char, _| char != " " }
    last ? cells.take(last + 1) : []
  end.drop_while(&:empty?).reverse.drop_while(&:empty?).reverse
  rows.map do |cells|
    current = nil
    html = +""
    cells.each do |char, role, background|
      foreground = role.to_s.start_with?("fg:") ? role.to_s.delete_prefix("fg:") : colors[role]
      css = { color: foreground, background: background }.filter_map do |property, value|
        next unless value

        rgb = value.is_a?(Integer) ? MermaidTerm::Output.rgb256(value) : MermaidTerm::Output.hex_rgb(value)
        "#{property}:#{format('#%02x%02x%02x', *rgb)}"
      end.join(";")
      if css != current
        html << "</span>" if current && !current.empty?
        html << "<span style=\"#{css}\">" unless css.empty?
        current = css
      end
      html << CGI.escapeHTML(char)
    end
    html << "</span>" if current && !current.empty?
    html
  end.join("\n")
end

cards = Dir.glob(File.expand_path("../spec/fixtures/**/*.mmd", __dir__)).sort.map do |path|
  source = File.read(path)
  name = File.basename(path, ".mmd")
  document = MermaidTerm.parse(source)
  unicode = document.render
  ascii = document.render(charset: :ascii)
  grid = MermaidTerm::Raster.rasterize(document.scene)
  variants = { Unicode: CGI.escapeHTML(unicode), ASCII: CGI.escapeHTML(ascii) }
  MermaidTerm::Output::THEMES.each_key { |theme| variants[theme] = themed_html(grid, theme) }
  panes = variants.map { |variant, picture| "<div><h3>#{variant}</h3><pre>#{picture}</pre></div>" }.join
  "<section><h2>#{CGI.escapeHTML(name)}</h2><div class=panes>#{panes}</div></section>"
end
html = "<!doctype html><html lang=\"en\"><head><meta charset=\"utf-8\">" \
       "<meta name=\"viewport\" content=\"width=device-width,initial-scale=1\"><title>MermaidTerm gallery</title>" \
       "<style>body{font:16px system-ui;background:#111827;color:#f9fafb;margin:2rem}" \
       "section{margin-bottom:3rem}.panes{display:flex;flex-wrap:wrap;gap:1rem}h3{margin:.25rem 0}" \
       "pre{background:#1f2937;padding:1rem;overflow:auto;color:#e5e7eb}</style>" \
       "</head><body><h1>MermaidTerm gallery</h1>#{cards.join}</body></html>"
destination = File.expand_path("../gallery.html", __dir__)
File.write(destination, html)
puts destination
