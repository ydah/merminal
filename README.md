# merminal

merminal is a pure Ruby terminal renderer for Mermaid diagrams. It runs without Node.js, a browser, external processes, or runtime gem dependencies. The Ruby API namespace is `Merminal`.

## Install

From this checkout:

```sh
gem build merminal.gemspec
gem install ./merminal-0.1.0.gem
```

Ruby 3.3 or newer is required.

## CLI

```sh
printf 'flowchart LR\nA[Start] --> B[Done]\n' | merminal
merminal --ascii diagram.mmd
merminal --check --strict diagram.mmd
merminal --markdown README.md
merminal --width 80 --theme solarized --color always diagram.mmd
```

`merminal --help` lists every option. When a requested width cannot hold the diagram, the CLI reports the actual width and keeps the full drawing.

## Ruby API

```ruby
require "merminal"

puts Merminal.render("flowchart LR\nA --> B")
document = Merminal.parse("pie\n\"A\" : 3\n\"B\" : 7")
warn document.diagnostics.map(&:to_s).join("\n")
puts document.render(charset: :ascii)

Merminal.markdown_blocks("```mermaid\ngraph LR\nA-->B\n```").each do |block|
  puts block.line, block.render
end
```

`Merminal.register` accepts a plugin with `diagram_type`, `keywords`, `parse(source)`, and `layout(ast, **options)` methods. `Document#scene` exposes immutable drawing primitives. The Scene and plugin interfaces are experimental.

## Supported diagrams

The parser accepts the Mermaid diagram declarations listed below. The core types
have dedicated parsers and layouts; the additional syntax types also have
diagram-specific semantic handling and terminal layouts. Core parser errors produce
line numbered diagnostics; additional syntax follows the documented subset and ignores
browser-only directives that have no terminal representation.

| Diagram | Syntax |
|---|---|
| Flowchart | [Flowchart](docs/syntax/flowchart.md) |
| Sequence | [Sequence](docs/syntax/sequence.md) |
| State | [State](docs/syntax/state.md) |
| Class | [Class](docs/syntax/class.md) |
| ER | [ER](docs/syntax/er.md) |
| Pie | [Pie](docs/syntax/pie.md) |
| XY chart | [XY chart](docs/syntax/xychart.md) |
| Gantt | [Gantt](docs/syntax/gantt.md) |
| Timeline | [Timeline](docs/syntax/timeline.md) |
| Mindmap | [Mindmap](docs/syntax/mindmap.md) |
| Additional syntax diagrams | [Use case, requirement, journey, GitGraph, C4, quadrant, Sankey, block, packet, Kanban, architecture, radar, treemap, Venn, Ishikawa, Wardley, TreeView, Cynefin, swimlane, Event Modeling, Agentflow, ZenUML, Railroad syntax diagrams](docs/syntax/additional.md) |

The [gallery](gallery.html) shows Unicode, ASCII, and the four color themes for every fixture.

Pie charts appear as horizontal bars because cell based terminals communicate proportions more clearly that way. Unicode ambiguous width defaults to one cell; set `ambiguous_width: 2` for terminals that use two. Emoji ZWJ sequences use the first grapheme code point's width, so some terminal fonts may differ. ASCII mode replaces non ASCII labels with `?`.

This is an independent implementation. Thanks to [termaid](https://github.com/fasouto/termaid), [mermaid-ascii](https://github.com/AlexanderGrooff/mermaid-ascii), and [beautiful-mermaid](https://github.com/lukilabs/beautiful-mermaid) for showing what terminal Mermaid tools can offer. Mermaid syntax belongs to the [Mermaid project](https://mermaid.js.org/).

## Known limitations

Self loops use outside lanes, and dense edge labels can still cross lines. [The structural layout decision](docs/adr/003-layout.md) and [scene boundary](docs/adr/002-scene.md) describe the architecture. Scene and plugin interfaces are experimental.

## Development

```sh
bundle install
bundle exec rake spec
bundle exec rake gallery
```

`rake unicode:generate` accepts `EAW_FILE` and `UCD_FILE` paths to the official Unicode 17.0 files. It regenerates the checked in width and box drawing tables.
