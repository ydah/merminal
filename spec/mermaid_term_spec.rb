# frozen_string_literal: true

require "spec_helper"
require "open3"

RSpec.describe MermaidTerm do
  it "measures CJK, combining marks and ambiguous characters in cells" do
    expect(MermaidTerm::Text.width("日本語abc")).to eq(9)
    expect(MermaidTerm::Text.width("e\u0301")).to eq(1)
    expect(MermaidTerm::Text.width("·", ambiguous_width: 2)).to eq(2)
    expect(MermaidTerm::Text.wrap("日本語abc", 4)).to eq(%w[日本 語ab c])
  end

  it "keeps original source line numbers through frontmatter and comments" do
    source = MermaidTerm::Source.parse("---\ntitle: Chart\nfoo: bar\n---\n%% comment\ngraph LR\nA-->B\n")
    expect(source.title).to eq("Chart")
    expect(source.line_map).to eq([6, 7])
    expect(source.diagnostics.first.severity).to eq(:info)
  end

  it "renders connected boxes in both charsets and all directions" do
    %w[TB BT LR RL].each do |direction|
      input = "graph #{direction}\nA[日本語]-->B[Done]"
      unicode = described_class.render(input)
      ascii = described_class.render(input, charset: :ascii)
      expect(unicode).to include("日本語", "Done")
      expect(ascii).to match(/\A[\x20-\x7e\n]*\z/)
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

  it "keeps randomly generated flowcharts inside their Scenes" do
    rng = Random.new(20_260_921)
    100.times do
      count = rng.rand(1..12)
      edges = Array.new(rng.rand(0..20)) do
        from, to = rng.rand(count), rng.rand(count)
        rng.rand(4).zero? ? "N#{from} -->|yes| N#{to}" : "N#{from} --> N#{to}"
      end
      source = "graph #{%w[TB BT LR RL].sample(random: rng)}\n" + edges.join("\n")
      document = described_class.parse(source)
      next if document.ast.nodes.empty?

      scene = document.scene
      output = document.render
      expect(output.lines.map { |line| MermaidTerm::Text.width(line.chomp) }.max).to be <= scene.width
      expect(output).to eq(document.render)
      boxes = scene.items.grep(MermaidTerm::Scene::Box).select { |item| item.role == :node_border }.map(&:rect)
      boxes.combination(2).each do |a, b|
        expect(a.x + a.width <= b.x || b.x + b.width <= a.x || a.y + a.height <= b.y || b.y + b.height <= a.y).to be(true)
      end
      scene.items.grep(MermaidTerm::Scene::Polyline).select { |item| item.role == :edge }.each do |edge|
        edge.points.each_cons(2) do |(x1, y1), (x2, y2)|
          distance = [(x2 - x1).abs, (y2 - y1).abs].max
          (0..distance).each do |step|
            x = x1 + (x2 <=> x1) * step
            y = y1 + (y2 <=> y1) * step
            expect(boxes.none? { |box| x > box.x && x < box.x + box.width - 1 && y > box.y && y < box.y + box.height - 1 }).to be(true)
          end
        end
      end
      scene.items.grep(MermaidTerm::Scene::Text).select { |item| item.role == :edge_label }.each do |label|
        right = label.x + MermaidTerm::Text.width(label.string)
        expect(boxes.none? { |box| label.y >= box.y && label.y < box.y + box.height && right > box.x && label.x < box.x + box.width }).to be(true)
      end
    end
  end

  it "accepts arbitrary bytes without leaking encoding exceptions" do
    rng = Random.new(118)
    100.times do
      bytes = Array.new(30) { rng.rand(256) }.pack("C*")
      expect { described_class.render("graph LR\n".b + bytes) }.not_to raise_error
    end
  end

  it "matches the reviewed Unicode gallery snapshots" do
    Dir.glob(File.expand_path("fixtures/*.mmd", __dir__)).each do |path|
      expect(described_class.render(File.read(path))).to match_snapshot(File.basename(path, ".mmd"))
    end
  end
end
