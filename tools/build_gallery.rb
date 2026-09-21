# frozen_string_literal: true

require "cgi"
require_relative "../lib/mermaid_term"

cards = Dir.glob(File.expand_path("../spec/fixtures/*.mmd", __dir__)).sort.map do |path|
  source = File.read(path)
  name = File.basename(path, ".mmd")
  unicode = MermaidTerm.render(source)
  ascii = MermaidTerm.render(source, charset: :ascii)
  "<section><h2>#{CGI.escapeHTML(name)}</h2><pre>#{CGI.escapeHTML(unicode)}</pre><pre>#{CGI.escapeHTML(ascii)}</pre></section>"
end
html = "<!doctype html><html lang=\"en\"><meta charset=\"utf-8\"><title>MermaidTerm gallery</title>" \
       "<style>body{font:16px system-ui;background:#111827;color:#f9fafb;margin:2rem}" \
       "section{margin-bottom:3rem}pre{display:inline-block;vertical-align:top;background:#1f2937;padding:1rem;margin-right:1rem;overflow:auto}</style>" \
       "<h1>MermaidTerm gallery</h1>#{cards.join}</html>"
destination = File.expand_path("../gallery.html", __dir__)
File.write(destination, html)
puts destination
