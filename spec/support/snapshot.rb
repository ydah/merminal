# frozen_string_literal: true

RSpec::Matchers.define :match_snapshot do |name|
  match do |actual|
    path = File.expand_path("../snapshots/#{name}.txt", __dir__)
    File.write(path, actual) if ENV["UPDATE_SNAPSHOTS"] == "1"
    @expected = File.exist?(path) ? File.read(path) : nil
    @actual = actual
    @expected == actual
  end

  failure_message do
    unless @expected
      next "missing snapshot #{name}; run UPDATE_SNAPSHOTS=1 bundle exec rake spec"
    end

    index = (0...[ @expected.length, @actual.length ].max).find { |offset| @expected[offset] != @actual[offset] }
    line = @expected[0...index].count("\n") + 1
    column = index - (@expected.rindex("\n", index) || -1)
    before = @expected[index]
    after = @actual[index]
    "snapshot #{name} differs at #{line}:#{column}: #{before ? format('U+%04X %s', before.ord, before) : 'EOF'} expected, " \
      "#{after ? format('U+%04X %s', after.ord, after) : 'EOF'} actual"
  end
end
