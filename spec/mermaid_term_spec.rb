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
end
