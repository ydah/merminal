# frozen_string_literal: true

# Usage: ruby tools/generate_east_asian_width.rb EastAsianWidth.txt UnicodeData.txt
eaw, ucd = ARGV
abort "pass EastAsianWidth.txt and UnicodeData.txt" unless eaw && ucd

ranges = { wide: [], ambiguous: [], zero: [] }
File.foreach(eaw) do |line|
  next unless line =~ /\A\s*([\dA-F]+)(?:\.\.([\dA-F]+))?\s*;\s*(W|F|A)\b/

  first = Regexp.last_match(1).to_i(16)
  last = (Regexp.last_match(2) || Regexp.last_match(1)).to_i(16)
  ranges[Regexp.last_match(3) == "A" ? :ambiguous : :wide] << [first, last]
end
pending = nil
File.foreach(ucd) do |line|
  fields = line.split(";", -1)
  code = fields[0].to_i(16)
  if fields[1].end_with?("First>")
    pending = [code, fields[2]]
  elsif fields[1].end_with?("Last>")
    ranges[:zero] << [pending[0], code] if %w[Mn Me].include?(pending[1])
    pending = nil
  elsif %w[Mn Me].include?(fields[2])
    ranges[:zero] << [code, code]
  end
end
ranges[:zero].concat([[0x200d, 0x200d], [0xfe00, 0xfe0f]])

def merge(ranges)
  ranges.sort.each_with_object([]) do |(first, last), result|
    if result.any? && first <= result[-1][1] + 1
      result[-1][1] = [result[-1][1], last].max
    else
      result << [first, last]
    end
  end
end

version = File.foreach(eaw).first(5).join[/EastAsianWidth-(\d+\.\d+\.\d+)/, 1] || "unknown"
output = "# frozen_string_literal: true\n# Unicode #{version}; generated from UCD files.\n\nmodule Merminal::Text\n"
ranges.each { |name, value| output << "  #{name.to_s.upcase} = Merminal::Shareable.make(#{merge(value).inspect})\n" }
output << "end\n"
File.write(File.expand_path("../lib/merminal/text/east_asian_width_table.rb", __dir__), output)
