# frozen_string_literal: true

require_relative "../lib/mermaid_term"

[10, 50, 200].each do |nodes|
  source = "graph LR\n" + (0...nodes - 1).map { |index| "N#{index} --> N#{index + 1}" }.join("\n")
  start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
  MermaidTerm.render(source)
  elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - start
  puts format("%3d nodes: %.1f ms", nodes, elapsed * 1000)
end
