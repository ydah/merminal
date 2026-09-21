# MermaidTerm

Pure Ruby terminal renderer for Mermaid diagrams. It runs without Node.js, a browser, external processes, or runtime gem dependencies.

## Install

From this checkout:

```sh
gem build mermaid_term.gemspec
gem install ./mermaid_term-0.1.0.gem
```

Ruby 3.3 or newer is required.

## CLI

```sh
printf 'flowchart LR\nA[Start] --> B[Done]\n' | mmterm
mmterm --ascii diagram.mmd
mmterm --check --strict diagram.mmd
mmterm --markdown README.md
mmterm --width 80 --theme solarized --color always diagram.mmd
```

`mmterm --help` lists every option. When a requested width cannot hold the diagram, the CLI reports the actual width and keeps the full drawing.

## Ruby API

```ruby
require "mermaid_term"

puts MermaidTerm.render("flowchart LR\nA --> B")
document = MermaidTerm.parse("pie\n\"A\" : 3\n\"B\" : 7")
warn document.diagnostics.map(&:to_s).join("\n")
puts document.render(charset: :ascii)

MermaidTerm.markdown_blocks("```mermaid\ngraph LR\nA-->B\n```").each do |block|
  puts block.line, block.render
end
```

`MermaidTerm.register` accepts a plugin with `diagram_type`, `keywords`, `parse(source)`, and `layout(ast, **options)` methods. `Document#scene` exposes immutable drawing primitives. The Scene and plugin interfaces are experimental.

## Supported diagrams

The parser accepts a documented subset of each Mermaid diagram type. Unsupported statements produce line numbered diagnostics; `--strict` treats errors as failures.

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

The [gallery](gallery.html) shows Unicode, ASCII, and the four color themes for every fixture.

Pie charts appear as horizontal bars because cell based terminals communicate proportions more clearly that way. Unicode ambiguous width defaults to one cell; set `ambiguous_width: 2` for terminals that use two. Emoji ZWJ sequences use the first grapheme code point's width, so some terminal fonts may differ. ASCII mode replaces non ASCII labels with `?`.

This is an independent implementation. Thanks to [termaid](https://github.com/fasouto/termaid), [mermaid-ascii](https://github.com/AlexanderGrooff/mermaid-ascii), and [beautiful-mermaid](https://github.com/lukilabs/beautiful-mermaid) for showing what terminal Mermaid tools can offer. Mermaid syntax belongs to the [Mermaid project](https://mermaid.js.org/).

## Known limitations

Self loops use outside lanes, and dense edge labels can still cross lines. [The layout decision](docs/adr/0004-layered.md) and [label decision](docs/adr/0006-labels.md) describe the routing. Scene and plugin interfaces are experimental.

## Development

```sh
bundle install
bundle exec rake spec
bundle exec rake gallery
```

`rake unicode:generate` accepts `EAW_FILE` and `UCD_FILE` paths to the official Unicode 17.0 files. It regenerates the checked in width and box drawing tables.
