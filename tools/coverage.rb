# frozen_string_literal: true

require "coverage"

Coverage.start(lines: true)
require "rspec/core"

result = RSpec::Core::Runner.run(["spec"])
files = Coverage.result.select { |path, _| path.start_with?(File.expand_path("../lib/mermaid_term", __dir__)) }
lines = files.values.flat_map { |data| data.fetch(:lines) }.compact
percent = lines.empty? ? 0 : (100.0 * lines.count(&:positive?) / lines.length)
puts format("Line coverage: %.1f%% (%d/%d)", percent, lines.count(&:positive?), lines.length)
exit(result.zero? && percent >= 90 ? 0 : 1)
