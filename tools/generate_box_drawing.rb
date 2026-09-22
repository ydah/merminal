# frozen_string_literal: true

# Usage: ruby tools/generate_box_drawing.rb UnicodeData.txt
path = ARGV.fetch(0) { abort "pass UnicodeData.txt" }
directions = { "UP" => [0], "RIGHT" => [1], "DOWN" => [2], "LEFT" => [3],
               "VERTICAL" => [0, 2], "HORIZONTAL" => [1, 3] }
weights = { "LIGHT" => 1, "SINGLE" => 1, "HEAVY" => 2, "DOUBLE" => 3 }
table = {}
File.foreach(path) do |line|
  fields = line.split(";", 3)
  code = fields[0].to_i(16)
  next unless code.between?(0x2500, 0x257f)

  name = fields[1].delete_prefix("BOX DRAWINGS ")
  next if name.match?(/DASH|ARC|DIAGONAL/)

  parts = name.split(" AND ")
  default = weights[name.split.first]
  arms = [0, 0, 0, 0]
  parts.each do |part|
    weight = part.split.filter_map { |word| weights[word] }.first || default
    next unless weight

    part.split.each { |word| directions[word]&.each { |index| arms[index] = weight } }
  end
  next if arms.all?(&:zero?)

  table[arms.join] ||= code.chr(Encoding::UTF_8)
end
light = table.keys.count { |key| key.chars.all? { |char| %w[0 1].include?(char) } }
abort "incomplete light table: #{light}/15" unless light == 15
output = +"# frozen_string_literal: true\n# Unicode 17.0.0; generated from UnicodeData.txt.\n\nmodule Merminal::Raster\n"
output << "  BOX_DRAWING = Merminal::Shareable.make(#{table.sort.to_h.inspect})\nend\n"
File.write(File.expand_path("../lib/merminal/raster/box_drawing_table.rb", __dir__), output)
