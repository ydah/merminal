# frozen_string_literal: true

module MermaidTerm::Diagrams
  # Participants and chronological events of a Mermaid sequence diagram.
  module Sequence
    Participant = Data.define(:id, :label, :actor)
    Event = Data.define(:kind, :from, :to, :text, :extra)
    Diagram = Data.define(:participants, :events)
    MESSAGE = /\A([\w.]+(?:-(?![-=>x])[\w.]+)*)\s*(-->>|->>|-->|->|--x|-x|--\)|-\))\s*([+-]?)([\w.-]+)\s*:\s*(.*)\z/
    def self.diagram_type = :sequence
    def self.keywords = %w[sequenceDiagram]

    def self.parse(source)
      participants = {}
      events = []
      findings = []
      blocks = []
      source.lines.drop(1).each_with_index do |line, index|
        statement = line.strip
        case statement
        when /\A(participant|actor)\s+(\S+)(?:\s+as\s+(.+))?\z/
          participants[Regexp.last_match(2)] = Participant.new(id: Regexp.last_match(2),
                                                                 label: Regexp.last_match(3) || Regexp.last_match(2),
                                                                 actor: Regexp.last_match(1) == "actor")
        when MESSAGE
          from, operator, activation, to, text = Regexp.last_match.captures
          [from, to].each { |id| participants[id] ||= Participant.new(id: id, label: id, actor: false) }
          events << Event.new(kind: :message, from: from, to: to, text: text, extra: operator)
          events << Event.new(kind: activation == "+" ? :activate : :deactivate,
                              from: activation == "+" ? to : from, to: nil, text: nil, extra: nil) unless activation.empty?
        when /\ANote\s+(left of|right of|over)\s+([^:]+):\s*(.*)\z/i
          side, ids, text = Regexp.last_match.captures
          ids.split(",").each { |id| participants[id.strip] ||= Participant.new(id: id.strip, label: id.strip, actor: false) }
          events << Event.new(kind: :note, from: ids.split(",").first.strip, to: ids.split(",").last.strip,
                              text: text.gsub(/<br\s*\/?\s*>/i, "\n"), extra: side.downcase)
        when /\A(loop|alt|opt|par|critical|break|rect)\b\s*(.*)\z/i
          blocks << Regexp.last_match(1)
          events << Event.new(kind: :block_start, from: nil, to: nil, text: Regexp.last_match(2), extra: Regexp.last_match(1))
        when /\A(else|and)\b\s*(.*)\z/i
          if blocks.empty?
            findings << MermaidTerm::Diagrams.finding("unexpected sequence branch", source, index + 1)
          else
            events << Event.new(kind: :block_else, from: nil, to: nil, text: Regexp.last_match(2), extra: Regexp.last_match(1))
          end
        when "end"
          if blocks.empty?
            findings << MermaidTerm::Diagrams.finding("unexpected end", source, index + 1)
          else
            blocks.pop
            events << Event.new(kind: :block_end, from: nil, to: nil, text: nil, extra: nil)
          end
        when /\A(activate|deactivate)\s+(\S+)\z/i
          id = Regexp.last_match(2)
          participants[id] ||= Participant.new(id: id, label: id, actor: false)
          events << Event.new(kind: Regexp.last_match(1).downcase.to_sym, from: id, to: nil, text: nil, extra: nil)
        when /\Aautonumber\b/
          events << Event.new(kind: :autonumber, from: nil, to: nil, text: nil, extra: nil)
        when ""
          next
        else
          findings << MermaidTerm::Diagrams.finding("unrecognized sequence statement", source, index + 1)
        end
      end
      findings << MermaidTerm::Diagrams.finding("unclosed sequence block", source, source.lines.length - 1) unless blocks.empty?
      [Diagram.new(participants: participants.values.freeze, events: events.freeze), findings]
    end

    def self.layout(ast, **)
      builder = Builder.new
      return builder.scene if ast.participants.empty?

      ids = ast.participants.map(&:id)
      gaps = ast.participants.each_cons(2).map do |left, right|
        [14, (Text.width(left.label) + 5) / 2 + (Text.width(right.label) + 5) / 2 + 4].max
      end
      numbered = false
      ast.events.each do |event|
        numbered = true if event.kind == :autonumber
        next unless event.kind == :message && event.from != event.to

        a, b = [ids.index(event.from), ids.index(event.to)].sort
        needed = Text.width(event.text) + 4 + (numbered ? 6 : 0)
        current = gaps[a...b].sum
        gaps[b - 1] += needed - current if current < needed
      end
      left_note = ast.events.select { |event| event.kind == :note && event.extra == "left of" && event.from == ids.first }
      left_margin = left_note.map { |event| Text.width(event.text) + 4 }.max.to_i
      first_width = Text.width(ast.participants.first.label) + 4
      centers = [[5 + left_margin, first_width / 2 + 1].max]
      gaps.each { |gap| centers << centers[-1] + gap }
      columns = ids.zip(centers).to_h
      rows = []
      y = 4
      autonumber = false
      number = 0
      ast.events.each do |event|
        next autonumber = true if event.kind == :autonumber

        label = event.text
        if event.kind == :message && autonumber
          number += 1
          label = "#{number}. #{label}"
        end
        rows << [event, y, label]
        y += case event.kind
             when :message then event.from == event.to ? 4 : 3
             when :note then label.count("\n") + 4
             when :block_start, :block_else then 2
             else 1
             end
      end
      bottom = y + 2
      ast.participants.each do |participant|
        center = columns.fetch(participant.id)
        width = Text.width(participant.label) + 4
        x = center - width / 2
        builder.box(x, 0, width, 3, rounded: participant.actor)
        builder.text(x + 2, 1, participant.label)
        builder.line([[center, 3], [center, bottom]], role: :muted, pattern: :dotted)
      end
      active = Hash.new { |hash, key| hash[key] = [] }
      blocks = []
      rows.each do |event, row, label|
        case event.kind
        when :message
          from = columns.fetch(event.from)
          to = columns.fetch(event.to)
          if from == to
            builder.text(from + 2, row, label, role: :edge_label)
            builder.line([[from, row + 1], [from + 5, row + 1], [from + 5, row + 3], [from, row + 3]],
                         pattern: event.extra.start_with?("--") ? :dotted : :solid)
            builder.marker(from + 1, row + 3, direction: :w, kind: marker_kind(event.extra))
          else
            left = [from, to].min
            builder.text(left + 1, row, label, role: :edge_label)
            builder.line([[from, row + 1], [to, row + 1]], pattern: event.extra.start_with?("--") ? :dotted : :solid)
            builder.marker(to + (to > from ? -1 : 1), row + 1, direction: to > from ? :e : :w,
                           kind: marker_kind(event.extra))
          end
        when :note
          from = columns.fetch(event.from)
          to = columns.fetch(event.to)
          width = [label.split("\n").map { |part| Text.width(part) }.max.to_i + 4,
                   event.extra == "over" ? (to - from).abs + 5 : 0].max
          x = event.extra == "left of" ? from - width - 2 : event.extra == "right of" ? to + 2 : (from + to - width) / 2
          x = [x, 0].max
          builder.box(x, row, width, label.count("\n") + 3, role: :container_border)
          builder.text(x + 2, row + 1, label)
        when :block_start
          blocks << [row, event.extra, label, blocks.length]
        when :block_else
          inset = blocks.length - 1
          builder.line([[inset, row], [centers.last + 6 - inset, row]], role: :container_border, pattern: :dotted)
          builder.text(inset + 2, row + 1, "#{event.extra} #{label}", role: :container_title)
        when :block_end
          start, kind, title, inset = blocks.pop
          next unless start

          builder.box(inset, start, centers.last + 7 - inset * 2, row - start + 1, role: :container_border)
          builder.text(inset + 2, start, "#{kind} #{title}", role: :container_title)
        when :activate
          active[event.from] << [row, active[event.from].length]
        when :deactivate
          start, depth = active[event.from].pop
          builder.box(columns.fetch(event.from) - 1 + depth * 2, start, 3, row - start + 1) if start
        end
      end
      active.each do |id, starts|
        starts.each { |start, depth| builder.box(columns.fetch(id) - 1 + depth * 2, start, 3, bottom - start + 1) }
      end
      builder.scene
    end

    def self.marker_kind(operator)
      operator.end_with?("x") ? :cross : operator.end_with?(")") ? :circle : :arrow
    end
  end
end
