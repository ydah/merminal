# frozen_string_literal: true

require "ripper"

Dir.glob("{lib,tools,exe}/**/*").select { |path| File.file?(path) && (path.end_with?(".rb") || path == "exe/mmterm") }.each do |path|
  abort "invalid Ruby syntax: #{path}" unless Ripper.sexp(File.read(path))
end
Dir.glob("lib/mermaid_term/diagrams/**/*.rb").each do |path|
  abort "box drawing literal in #{path}" if File.read(path).match?(/[\u2500-\u257F]/)
end
Dir.glob("lib/**/*.rb").each do |path|
  abort "display-width shortcut in #{path}" if File.read(path).match?(/\.(?:ljust|rjust|center)\s*\(/)
end
puts "repository checks passed"
