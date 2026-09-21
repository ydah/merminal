# frozen_string_literal: true

require_relative "../lib/mermaid_term"

[ [10, 12, 15], [50, 70, 150], [200, 300, 2000] ].each do |nodes, edges, target_ms|
  links = (0...nodes - 1).map { |index| "N#{index} --> N#{index + 1}" }
  (edges - links.length).times { |index| links << "N#{index % (nodes - 3)} --> N#{index % (nodes - 3) + 3}" }
  source = "graph LR\n" + links.join("\n")
  start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
  MermaidTerm.render(source)
  elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - start
  puts format("%3d nodes / %3d edges: %.1f ms (target %d ms)", nodes, edges, elapsed * 1000, target_ms)
  warn "benchmark target exceeded" if elapsed * 1000 > target_ms
end

source = "sequenceDiagram\n" + (0...10).map { |index| "participant P#{index}" }.join("\n") + "\n" +
         (0...100).map { |index| "P#{index % 10}->>P#{(index + 1) % 10}: message #{index}" }.join("\n")
start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
MermaidTerm.render(source)
elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - start
puts format("sequence 10 participants / 100 messages: %.1f ms (target 50 ms)", elapsed * 1000)
warn "benchmark target exceeded" if elapsed * 1000 > 50
