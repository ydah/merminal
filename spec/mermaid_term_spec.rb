# frozen_string_literal: true

require "spec_helper"
require "open3"
require "tmpdir"

RSpec.describe MermaidTerm do
  it "reproduces property runs from a seed" do
    observed = []
    property(runs: 3, seed: 42) { |rng, _| observed << rng.rand(100) }
    expected_rng = Random.new(Integer(ENV.fetch("SEED", 42)))
    expect(observed).to eq(Array.new(3) { expected_rng.rand(100) })
  end

  it "reports a snapshot mismatch with its cell and code points" do
    updating = ENV.delete("UPDATE_SNAPSHOTS")
    matcher = match_snapshot("scene_demo_unicode")
    expect(matcher.matches?("x")).to be(false)
    expect(matcher.failure_message).to match(/1:1: U\+[0-9A-F]{4} .* expected, U\+0078 x actual/)
  ensure
    ENV["UPDATE_SNAPSHOTS"] = updating if updating
  end

  it "measures CJK, combining marks and ambiguous characters in cells" do
    expect(MermaidTerm::Text.width("abc")).to eq(3)
    expect(MermaidTerm::Text.width("日本語abc")).to eq(9)
    expect(MermaidTerm::Text.width("한글")).to eq(4)
    expect(MermaidTerm::Text.width("ｶﾅ")).to eq(2)
    expect(MermaidTerm::Text.width("ＡＢ")).to eq(4)
    expect(MermaidTerm::Text.width("e\u0301")).to eq(1)
    expect(MermaidTerm::Text.width("a\uFE0F")).to eq(1)
    expect(MermaidTerm::Text.width("·", ambiguous_width: 2)).to eq(2)
    expect(MermaidTerm::Text.wrap("日本語abc", 4)).to eq(%w[日本 語ab c])
  end

  it "covers every light box-drawing arm mask and sorted width ranges" do
    table = MermaidTerm::Raster::BOX_DRAWING
    (1..15).each do |mask|
      key = 4.times.map { |index| mask[index] == 1 ? 1 : 0 }.join
      expect(table).to have_key(key)
    end
    %w[┼ ╋ ╬ ┿ ╪].each { |character| expect(table).to have_value(character) }
    %i[WIDE ZERO AMBIGUOUS].each do |name|
      ranges = MermaidTerm::Text.const_get(name)
      expect(ranges.each_cons(2).all? { |a, b| a.last < b.first }).to be(true)
    end
  end

  it "keeps original source line numbers through frontmatter and comments" do
    source = MermaidTerm::Source.parse("---\ntitle: Chart\nfoo: bar\n---\n%% comment\ngraph LR\nA-->B\n")
    expect(source.title).to eq("Chart")
    expect(source.line_map).to eq([6, 7])
    expect(source.diagnostics.first.severity).to eq(:info)
  end

  it "handles empty and malformed source directives without losing lines" do
    expect(MermaidTerm::Source.parse("").lines).to be_empty
    source = MermaidTerm::Source.parse("---\ntitle: Plan\n---\n%%{init: {'theme':'solarized'}}%%\n%% note\ngraph LR\nA-->B\n")
    expect([source.title, source.directives["theme"], source.line_map]).to eq(["Plan", "solarized", [6, 7]])
    invalid = MermaidTerm::Source.parse("%%{init: broken}%%\ngraph LR\n")
    expect(invalid.diagnostics.map(&:severity)).to include(:warning)
    unclosed = MermaidTerm::Source.parse("---\ntitle: Plan\n")
    expect(unclosed.diagnostics.map(&:message)).to include("unclosed frontmatter")
  end

  it "renders connected boxes in both charsets and all directions" do
    %w[TB BT LR RL].each do |direction|
      input = "graph #{direction}\nA[日本語]-->B[Done]"
      unicode = described_class.render(input)
      ascii = described_class.render(input, charset: :ascii)
      expect(unicode).to include("日本語", "Done")
      expect(ascii).to match(/\A[\x20-\x7e\n]*\z/)
      expect(ascii).to include("??????")
      expect(unicode).to eq(described_class.render(input))
    end
  end

  it "reports malformed statements and can reject them in strict mode" do
    input = "graph LR\nA[broken\nB-->C"
    document = described_class.parse(input)
    expect(document.diagnostics.map(&:severity)).to include(:error)
    expect(document.ast.nodes.map(&:id)).to include("B", "C")
    expect { described_class.parse(input, strict: true) }.to raise_error(MermaidTerm::SyntaxError)
  end

  it "rasterizes a junction and wide text without losing alignment" do
    scene = MermaidTerm::Scene
    items = [
      scene::Box.new(rect: scene::Rect.new(x: 0, y: 0, width: 8, height: 3), stroke: scene::LIGHT,
                     corners: :sharp, role: :node_border, layer: :node),
      scene::Polyline.new(points: [[3, 0], [3, 2]], stroke: scene::LIGHT, role: :edge, layer: :edge),
      scene::Text.new(x: 2, y: 1, string: "日", role: :node_text, layer: :label, emphasis: nil)
    ]
    grid = MermaidTerm::Raster.rasterize(scene.new(width: 8, height: 3, items: items))
    expect(MermaidTerm::Output.render(grid)).to include("┬", "日")
  end

  it "renders the hand-built Scene demo in both charsets" do
    demo = File.expand_path("../examples/scene_demo.rb", __dir__)
    { unicode: [], ascii: ["--ascii"] }.each do |charset, arguments|
      output, errors, status = Open3.capture3(RbConfig.ruby, demo, *arguments)
      expect(status.exitstatus).to eq(0)
      expect(errors).to be_empty
      expect(output).to match_snapshot("scene_demo_#{charset}")
    end
  end

  it "separates independent edge crossings in bridge mode" do
    scene = MermaidTerm::Scene
    items = [
      scene::Polyline.new(points: [[0, 2], [4, 2]], stroke: scene::LIGHT, role: :edge, layer: :edge),
      scene::Polyline.new(points: [[2, 0], [2, 4]], stroke: scene::LIGHT, role: :edge, layer: :edge)
    ]
    picture = scene.new(width: 5, height: 5, items: items)
    expect(MermaidTerm::Output.render(MermaidTerm::Raster.rasterize(picture))).to include("╶─┼─╴")
    expect(MermaidTerm::Output.render(MermaidTerm::Raster.rasterize(picture, crossings: :bridge))).to include("╶─│─╴")
  end

  it "parses modern shapes and applies Mermaid colors" do
    source = "flowchart LR\nA@{ shape: diamond } --> B[/Result/]\nclassDef hot fill:#f9f,stroke:#333,color:#000\nclass A hot"
    document = described_class.parse(source)
    expect(document.ast.nodes.map(&:shape)).to eq(%i[decision parallelogram])
    previous_no_color = ENV.delete("NO_COLOR")
    previous_color = ENV["COLORTERM"]
    ENV["COLORTERM"] = "truecolor"
    expect(document.render(color: true)).to include("48;2;255;153;255", "38;2;51;51;51")
  ensure
    ENV["NO_COLOR"] = previous_no_color if previous_no_color
    ENV["COLORTERM"] = previous_color
  end

  it "keeps semicolons inside quoted labels" do
    document = described_class.parse('graph LR; A["x;y"]; A-->B')
    expect(document.ast.nodes.map(&:label)).to eq(["x;y", "B"])
    expect(document.ast.edges.length).to eq(1)
    expect(document.diagnostics).to be_empty
  end

  it "keeps closing brackets inside quoted labels" do
    document = described_class.parse('graph LR; A["x]y;z"] --> B')
    expect(document.ast.nodes.map(&:label)).to eq(["x]y;z", "B"])
    expect(document.diagnostics).to be_empty
    slanted = described_class.parse('graph LR; A[/"x]y"/] --> B')
    expect(slanted.ast.nodes.first.label).to eq("x]y")
  end

  it "gives converging arrows separate input cells" do
    scene = described_class.parse("flowchart TB\nA-->C\nB-->C").scene
    arrowheads = scene.items.grep(MermaidTerm::Scene::Marker).select { |item| item.kind == :arrow }
    expect(arrowheads.map { |item| [item.x, item.y] }.uniq.length).to eq(2)
  end

  it "shares channel tracks for disjoint edges and branches" do
    ["graph TB\nA-->B\nC-->D", "graph TB\nA-->B\nA-->C"].each do |source|
      edges = described_class.parse(source).scene.items.grep(MermaidTerm::Scene::Polyline)
                             .select { |item| item.role == :edge }
      expect(edges.map { |edge| edge.points[1][1] }.uniq.length).to eq(1)
    end
    edges = described_class.parse("graph TB\nA-->C\nA-->D\nB-->C\nB-->D").scene.items
                           .grep(MermaidTerm::Scene::Polyline).select { |item| item.role == :edge }
    expect(edges.first(2).map { |edge| edge.points[1][1] }.uniq.length).to eq(1)
    expect(edges.last(2).map { |edge| edge.points[1][1] }.uniq.length).to eq(1)
    expect(edges.first.points[1][1]).not_to eq(edges.last.points[1][1])
  end

  it "separates channel tracks when edge labels would overlap" do
    source = "graph TB\nA -->|first-long-label| B\nC -->|second-long-label| D"
    labels = described_class.parse(source).scene.items.grep(MermaidTerm::Scene::Text)
                            .select { |item| item.role == :edge_label }
    expect(labels.map(&:y).uniq.length).to eq(2)
    expect(described_class.render(source)).to include("first-long-label", "second-long-label")
  end

  it "fits the public render API without truncating content" do
    source = "graph TB\nA[Hello] --> B[World]\nA --> C[Other]"
    compact = described_class.render(source, width: 24)
    expect(compact.lines.map { |line| MermaidTerm::Text.width(line.chomp) }.max).to be <= 24
    expect(compact).to include("Hello", "World", "Other")
  end

  it "extracts only matching Markdown fences" do
    markdown = "````ruby\n```mermaid\ngraph LR\nA-->B\n````\n~~~mermaid\ngraph LR\nB-->C\n~~~\n"
    expect(described_class.markdown_blocks(markdown).map(&:line)).to eq([7])
  end

  it "runs the CLI for a pipe and reports check errors" do
    exe = File.expand_path("../exe/mmterm", __dir__)
    output, errors, status = Open3.capture3(RbConfig.ruby, exe, "--ascii", stdin_data: "graph LR\nA-->B\n")
    expect(status.exitstatus).to eq(0)
    expect(errors).to be_empty
    expect(output).to include("A", "B", ">")
    _, errors, status = Open3.capture3(RbConfig.ruby, exe, "--check", stdin_data: "graph LR\nA[bad\n")
    expect(status.exitstatus).to eq(1)
    expect(errors).to include("unclosed node shape")
  end

  it "handles CLI files, Markdown, output, color, and exit codes" do
    exe = File.expand_path("../exe/mmterm", __dir__)
    Dir.mktmpdir do |directory|
      markdown = File.join(directory, "diagrams.md")
      output_path = File.join(directory, "picture.txt")
      File.write(markdown, "# Example\n```mermaid\ngraph LR\nA-->B\n```\n")
      output, errors, status = Open3.capture3(RbConfig.ruby, exe, "--ascii", "-o", output_path, markdown)
      expect([status.exitstatus, output, errors]).to eq([0, "", ""])
      expect(File.read(output_path)).to include("A", "B", ">")

      output, errors, status = Open3.capture3({ "NO_COLOR" => nil, "FORCE_COLOR" => "1" },
                                              RbConfig.ruby, exe, "--color", "always", markdown)
      expect([status.exitstatus, errors]).to eq([0, ""])
      expect(output).to include("\e[")
    end
    _, _, status = Open3.capture3(RbConfig.ruby, exe, "--strict", stdin_data: "graph LR\nA[bad\n")
    expect(status.exitstatus).to eq(1)
    _, _, status = Open3.capture3(RbConfig.ruby, exe, stdin_data: "unknownDiagram\n")
    expect(status.exitstatus).to eq(3)
    _, _, status = Open3.capture3(RbConfig.ruby, exe, "--width", "0", stdin_data: "graph LR\nA-->B\n")
    expect(status.exitstatus).to eq(2)
  end

  it "renders every registered diagram with Unicode and ASCII" do
    samples = {
      sequence: "sequenceDiagram\nparticipant A as Alice\nparticipant B as Bob\nA->>B: Hello\nB-->>A: Hi\n",
      state: "stateDiagram-v2\n[*] --> Idle\nIdle --> Busy : work\nBusy --> [*]\n",
      class: "classDiagram\nclass Animal {\n+name: String\n+speak()\n}\nAnimal <|-- Dog\n",
      er: "erDiagram\nCUSTOMER ||--o{ ORDER : places\nCUSTOMER {\nstring name PK\n}\n",
      pie: "pie showData\ntitle Sales\n\"A\" : 30\n\"B\" : 70\n",
      xychart: "xychart-beta\ntitle Revenue\nx-axis [Jan, Feb, Mar]\nbar [2, 4, 3]\nline [1, 3, 5]\n",
      gantt: "gantt\ndateFormat YYYY-MM-DD\nsection Work\nPlan :done, p1, 2026-01-01, 3d\nBuild :active, b1, after p1, 5d\n",
      timeline: "timeline\ntitle History\n2024 : Alpha\n2025 : Beta\n",
      mindmap: "mindmap\nroot((Root))\n  A\n    A1\n  B\n"
    }
    expect(described_class.diagram_types).to contain_exactly(:flowchart, *samples.keys)
    samples.each_value do |source|
      document = described_class.parse(source)
      expect(document.diagnostics.select { |diagnostic| diagnostic.severity == :error }).to be_empty
      expect(document.render).not_to be_empty
      expect(document.render(charset: :ascii)).to match(/\A[\x20-\x7e\n]*\z/)
    end
  end

  it "registers a diagram plugin and rejects duplicate keywords" do
    plugin = Module.new do
      def self.diagram_type = :sample
      def self.keywords = %w[sampleDiagram]
      def self.parse(_source) = [nil, []]
      def self.layout(_ast, **) = MermaidTerm::Scene.new(width: 1, height: 1,
                                                         items: [MermaidTerm::Scene::Glyph.new(x: 0, y: 0, char: "X",
                                                                                               role: :node_text, layer: :label)])
    end
    registry = MermaidTerm.instance_variable_get(:@plugins)
    described_class.register(plugin)
    expect(described_class.render("sampleDiagram")).to eq("X")
    expect { described_class.register(plugin) }.to raise_error(ArgumentError, /duplicate/)
  ensure
    registry&.delete(plugin)
  end

  it "returns shareable parsed graphs and Scenes" do
    document = described_class.parse("graph LR\nA-->B")
    expect(Ractor.shareable?(document.ast)).to be(true)
    expect(Ractor.shareable?(document.scene)).to be(true)
  end

  it "keeps wide first sequence participants inside the Scene" do
    source = "sequenceDiagram\nparticipant A as A very long first participant\nA->>B: Hello\n"
    expect { described_class.render(source) }.not_to raise_error
  end

  it "can repeat sequence participant boxes at the bottom" do
    source = "sequenceDiagram\nparticipant A as Alice\nparticipant B as Bob\nA->>B: Hello\n"
    output = described_class.render(source, repeat_participants: true)
    expect(output.scan("Alice").length).to eq(2)
    expect(output.scan("Bob").length).to eq(2)
  end

  it "keeps randomly generated flowcharts inside their Scenes" do
    property(runs: 500, seed: 20_260_921) do |rng, record|
      count = rng.rand(1..12)
      edges = Array.new(rng.rand(0..20)) do
        from, to = rng.rand(count), rng.rand(count)
        rng.rand(4).zero? ? "N#{from} -->|yes| N#{to}" : "N#{from} --> N#{to}"
      end
      source = "graph #{%w[TB BT LR RL].sample(random: rng)}\n" + edges.join("\n")
      record.call(source)
      assert_flowchart_properties(source)
    end
  end

  it "keeps every flowchart fixture inside its Scene" do
    paths = Dir.glob(File.expand_path("fixtures/{flowchart*,subgraph*}/**/*.mmd", __dir__))
    paths << File.expand_path("fixtures/flowchart.mmd", __dir__)
    expect(paths.length).to be >= 40
    paths.each { |path| assert_flowchart_properties(File.read(path)) }
  end

  it "contains nested subgraphs without crossing their sibling frames" do
    Dir.glob(File.expand_path("fixtures/subgraph_cases/*.mmd", __dir__)).each do |path|
      document = described_class.parse(File.read(path))
      groups = document.ast.subgraphs
      frames = document.scene.items.grep(MermaidTerm::Scene::Box).select { |item| item.role == :container_border }.map(&:rect)
      nodes = document.ast.nodes.map(&:id).zip(document.scene.items.grep(MermaidTerm::Scene::Box)
                                  .select { |item| item.role == :node_border }.map(&:rect)).to_h
      expect(frames.length).to eq(groups.length)
      groups.zip(frames).each do |group, frame|
        group.node_ids.uniq.each do |id|
          node = nodes.fetch(id)
          expect(frame.x <= node.x && frame.y <= node.y &&
                 frame.x + frame.width >= node.x + node.width &&
                 frame.y + frame.height >= node.y + node.height).to be(true)
        end
      end
      edges = document.scene.items.grep(MermaidTerm::Scene::Polyline).select { |item| item.role == :edge }
      document.ast.edges.zip(edges).each do |edge, line|
        groups.zip(frames).each do |group, frame|
          next if group.node_ids.include?(edge.from) || group.node_ids.include?(edge.to)

          line.points.each_cons(2) do |(x1, y1), (x2, y2)|
            distance = [(x2 - x1).abs, (y2 - y1).abs].max
            (0..distance).each do |step|
              x = x1 + (x2 <=> x1) * step
              y = y1 + (y2 <=> y1) * step
              expect(x <= frame.x || x >= frame.x + frame.width - 1 ||
                     y <= frame.y || y >= frame.y + frame.height - 1).to be(true)
            end
          end
        end
      end
      frames.combination(2).each do |a, b|
        disjoint = a.x + a.width <= b.x || b.x + b.width <= a.x ||
                   a.y + a.height <= b.y || b.y + b.height <= a.y
        contains = lambda do |outer, inner|
          outer.x <= inner.x && outer.y <= inner.y &&
            outer.x + outer.width >= inner.x + inner.width &&
            outer.y + outer.height >= inner.y + inner.height
        end
        expect(disjoint || contains.call(a, b) || contains.call(b, a)).to be(true)
      end
    end
  end

  it "clips group endpoint edges to the group frame" do
    source = File.read(File.expand_path("fixtures/subgraph_cases/group_10_endpoint.mmd", __dir__))
    scene = described_class.parse(source).scene
    frames = scene.items.grep(MermaidTerm::Scene::Box).select { |item| item.role == :container_border }.map(&:rect)
    edges = scene.items.grep(MermaidTerm::Scene::Polyline).select { |item| item.role == :edge }
    inner = frames.last
    expect(edges.first.points.last[1]).to eq(inner.y)
    expect(edges.last.points.first[0]).to eq(inner.x + inner.width - 1)
  end

  it "accepts arbitrary bytes without leaking encoding exceptions" do
    rng = Random.new(118)
    headers = %w[graph sequenceDiagram stateDiagram-v2 classDiagram erDiagram pie xychart-beta gantt timeline mindmap]
    headers.each do |header|
      20.times do
        bytes = Array.new(30) { rng.rand(256) }.pack("C*")
        expect { described_class.render("#{header}\n".b + bytes) }.not_to raise_error
      end
    end
  end

  it "survives truncated and mutated diagrams" do
    rng = Random.new(5_503)
    Dir.glob(File.expand_path("fixtures/*.mmd", __dir__)).each do |path|
      source = File.read(path)
      50.times do
        truncated = source.byteslice(0, rng.rand(source.bytesize))
        mutated = source.dup
        mutated[rng.rand(mutated.length)] = ["@", "}", "[", "\n"].sample(random: rng)
        [truncated, mutated].each do |input|
          begin
            described_class.render(input)
          rescue MermaidTerm::UnsupportedDiagramError, MermaidTerm::SyntaxError
            nil
          rescue RangeError => error
            raise "#{path}: #{input.inspect}: #{error.message}"
          end
        end
      end
    end
  end

  it "matches the reviewed Unicode gallery snapshots" do
    Dir.glob(File.expand_path("fixtures/**/*.mmd", __dir__)).each do |path|
      document = described_class.parse(File.read(path))
      expect(document.diagnostics.select { |diagnostic| diagnostic.severity == :error }).to be_empty
      expect(document.render).to match_snapshot(File.basename(path, ".mmd"))
    end
  end

  def assert_flowchart_properties(source)
    document = described_class.parse(source)
    return if document.ast.nodes.empty?

    scene = document.scene
    output = document.render
    expect(output.lines.map { |line| MermaidTerm::Text.width(line.chomp) }.max).to be <= scene.width
    expect(output).to eq(document.render)
    boxes = scene.items.grep(MermaidTerm::Scene::Box).select { |item| item.role == :node_border }.map(&:rect)
    frames = document.ast.subgraphs.map(&:id).zip(scene.items.grep(MermaidTerm::Scene::Box)
                     .select { |item| item.role == :container_border }.map(&:rect)).to_h
    boxes.combination(2).each do |a, b|
      expect(a.x + a.width <= b.x || b.x + b.width <= a.x || a.y + a.height <= b.y || b.y + b.height <= a.y).to be(true)
    end
    lines = scene.items.grep(MermaidTerm::Scene::Polyline).select { |item| item.role == :edge }
    document.ast.edges.reject { |edge| edge.stroke == :invisible }.zip(lines).each do |ast_edge, edge|
      group_ids = document.ast.styles["group_edge:#{ast_edge.id}"] || []
      endpoints = boxes + group_ids.filter_map { |id| frames[id] }
      [edge.points.first, edge.points.last].each do |x, y|
        expect(endpoints.any? do |box|
          x >= box.x && x < box.x + box.width && y >= box.y && y < box.y + box.height &&
            (x == box.x || x == box.x + box.width - 1 || y == box.y || y == box.y + box.height - 1)
        end).to be(true)
      end
      edge.points.each_cons(2) do |(x1, y1), (x2, y2)|
        distance = [(x2 - x1).abs, (y2 - y1).abs].max
        (0..distance).each do |step|
          x = x1 + (x2 <=> x1) * step
          y = y1 + (y2 <=> y1) * step
          expect(boxes.none? { |box| x > box.x && x < box.x + box.width - 1 && y > box.y && y < box.y + box.height - 1 }).to be(true)
        end
      end
    end
    labels = scene.items.grep(MermaidTerm::Scene::Text).select { |item| item.role == :edge_label }
    labels.each do |label|
      right = label.x + MermaidTerm::Text.width(label.string)
      expect(boxes.none? { |box| label.y >= box.y && label.y < box.y + box.height && right > box.x && label.x < box.x + box.width }).to be(true)
    end
    labels.combination(2).each do |a, b|
      next unless a.y == b.y

      expect(a.x + MermaidTerm::Text.width(a.string) <= b.x ||
             b.x + MermaidTerm::Text.width(b.string) <= a.x).to be(true)
    end
    document.ast.nodes.each { |node| expect(output).to include(node.label) }
    expect(document.render(charset: :ascii)).to match(/\A[\x20-\x7e\n]*\z/)
  end
end
