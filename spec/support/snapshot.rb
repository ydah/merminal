# frozen_string_literal: true

RSpec::Matchers.define :match_snapshot do |name|
  match do |actual|
    path = File.expand_path("../snapshots/#{name}.txt", __dir__)
    @actual = actual
    if !File.exist?(path) && ENV["UPDATE_SNAPSHOTS"] != "1"
      File.write(path, actual)
      RSpec::Core::Pending.mark_pending!(RSpec.current_example, "new snapshot #{name} needs review")
      @expected = nil
      next false
    end

    File.write(path, actual) if ENV["UPDATE_SNAPSHOTS"] == "1"
    @expected = File.read(path)
    @expected == actual
  end

  failure_message do
    unless @expected
      next "missing snapshot #{name}; run UPDATE_SNAPSHOTS=1 bundle exec rake spec"
    end

    index = (0...[ @expected.length, @actual.length ].max).find { |offset| @expected[offset] != @actual[offset] }
    line = @expected[0...index].count("\n") + 1
    start = (@expected.rindex("\n", index) || -1) + 1
    column = Merminal::Text.width(@expected[start...index]) + 1
    before = @expected[index]
    after = @actual[index]
    "snapshot #{name} differs at #{line}:#{column}: #{before ? format('U+%04X %s', before.ord, before) : 'EOF'} expected, " \
      "#{after ? format('U+%04X %s', after.ord, after) : 'EOF'} actual"
  end
end
