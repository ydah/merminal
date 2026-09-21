# frozen_string_literal: true

require "date"

module MermaidTerm::Diagrams
  # Date based Mermaid Gantt chart.
  module Gantt
    Task = Data.define(:name, :state, :start_date, :end_date, :section)
    Diagram = Data.define(:title, :tasks)
    def self.diagram_type = :gantt
    def self.keywords = %w[gantt]

    def self.parse(source)
      title = source.title
      format = "%Y-%m-%d"
      section = nil
      weekends = false
      tasks = []
      by_id = {}
      findings = []
      source.lines.drop(1).each_with_index do |line, index|
        statement = line.strip
        case statement
        when /\Atitle\s+(.+)\z/
          title = Regexp.last_match(1)
        when /\AdateFormat\s+(.+)\z/
          format = Regexp.last_match(1).gsub("YYYY", "%Y").gsub("MM", "%m").gsub("DD", "%d")
        when /\Asection\s+(.+)\z/
          section = Regexp.last_match(1)
        when /\Aexcludes\s+weekends\z/
          weekends = true
        when /\A([^:]+)\s*:\s*(.+)\z/
          name = Regexp.last_match(1).strip
          pieces = Regexp.last_match(2).split(",").map(&:strip)
          state = pieces.grep(/\A(?:done|active|crit|milestone)\z/).first&.to_sym
          pieces.delete(state.to_s) if state
          id = pieces.length > 2 ? pieces.shift : nil
          start_token = pieces.shift
          duration_token = pieces.shift
          start_date = if start_token&.start_with?("after ")
                         by_id[start_token.delete_prefix("after ")]&.end_date
                       else
                         Date.strptime(start_token.to_s, format)
                       end
          raise ArgumentError, "unknown start date" unless start_date

          end_date = if duration_token =~ /\A(\d+)([dw])\z/
                       days = Regexp.last_match(1).to_i * (Regexp.last_match(2) == "w" ? 7 : 1)
                       advance(start_date, days, weekends)
                     else
                       Date.strptime(duration_token.to_s, format)
                     end
          task = Task.new(name: name, state: state, start_date: start_date, end_date: end_date, section: section)
          tasks << task
          by_id[id] = task if id
        when "", /\A(?:axisFormat|todayMarker|tickInterval)\b/
          next
        else
          findings << MermaidTerm::Diagrams.finding("unrecognized gantt statement", source, index + 1)
        end
      rescue ArgumentError
        findings << MermaidTerm::Diagrams.finding("invalid gantt task", source, index + 1)
      end
      [Diagram.new(title: title, tasks: tasks.freeze), findings]
    end

    def self.advance(start_date, days, weekends)
      date = start_date
      days.times do
        date += 1
        date += 1 while weekends && [0, 6].include?(date.wday)
      end
      date
    end

    def self.layout(ast, charset: :unicode, **)
      builder = Builder.new
      return builder.scene if ast.tasks.empty?

      y = 0
      if ast.title
        builder.text(0, y, ast.title, role: :emphasis)
        y += 2
      end
      first = ast.tasks.map(&:start_date).min
      last = ast.tasks.map(&:end_date).max
      span = [(last - first).to_i, 1].max
      label_width = ast.tasks.map { |task| Text.width(task.name) }.max
      bar_left = label_width + 3
      builder.text(bar_left, y, "#{first} — #{last}", role: :axis_label)
      y += 1
      section = nil
      ast.tasks.each do |task|
        if task.section && task.section != section
          section = task.section
          builder.text(0, y, section, role: :container_title)
          y += 1
        end
        builder.text(0, y, Text.pad(task.name, label_width))
        offset = ((task.start_date - first).to_f / span * 40).round
        size = [((task.end_date - task.start_date).to_f / span * 40).round, 1].max
        char = task.state == :milestone ? (charset == :ascii ? "*" : "◆") : (charset == :ascii ? "#" : "█")
        builder.text(bar_left + offset, y, char * (task.state == :milestone ? 1 : size), role: task.state == :done ? :muted : :series_1)
        y += 1
      end
      builder.scene
    end
  end
end
