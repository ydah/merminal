# frozen_string_literal: true

module MermaidTerm::Diagrams
  # Ordered timeline rendered as a vertical list.
  module Timeline
    Event = Data.define(:period, :text, :section)
    Diagram = Data.define(:title, :events)
    def self.diagram_type = :timeline
    def self.keywords = %w[timeline]

    def self.parse(source)
      title = source.title
      section = nil
      events = []
      findings = []
      period = nil
      source.lines.drop(1).each_with_index do |line, index|
        case line.strip
        when /\Atitle\s+(.+)\z/
          title = Regexp.last_match(1)
        when /\Asection\s+(.+)\z/
          section = Regexp.last_match(1)
        when /\A([^:]+?)\s*:\s*(.+)\z/
          period = Regexp.last_match(1).strip
          events << Event.new(period: period, text: Regexp.last_match(2).strip, section: section)
        when /\A:\s*(.+)\z/
          events << Event.new(period: period, text: Regexp.last_match(1).strip, section: section) if period
        when ""
          next
        else
          findings << MermaidTerm::Diagrams.finding("unrecognized timeline statement", source, index + 1)
        end
      end
      [Diagram.new(title: title, events: events.freeze), findings]
    end

    def self.layout(ast, charset: :unicode, **)
      builder = Builder.new
      y = 0
      if ast.title
        builder.text(0, y, ast.title, role: :emphasis)
        y += 2
      end
      period_width = ast.events.map { |event| Text.width(event.period.to_s) }.max.to_i
      section = nil
      ast.events.each do |event|
        if event.section && event.section != section
          builder.text(0, y, event.section, role: :container_title)
          y += 1
          section = event.section
        end
        builder.text(0, y, Text.pad(event.period.to_s, period_width), role: :axis_label)
        builder.text(period_width + 1, y, charset == :ascii ? "|" : "●", role: :marker)
        builder.text(period_width + 3, y, event.text)
        y += 1
      end
      builder.scene
    end
  end
end
