<div align="center">

# merminal

**Pure Ruby terminal renderer for Mermaid diagrams in Unicode and ASCII terminals.**

[![Gem version](https://img.shields.io/gem/v/merminal?color=4f8a8b)](https://rubygems.org/gems/merminal)
[![CI](https://github.com/ydah/merminal/actions/workflows/main.yml/badge.svg)](https://github.com/ydah/merminal/actions/workflows/main.yml)
[![Ruby 3.3+](https://img.shields.io/badge/Ruby-3.3%2B-CC342D)](merminal.gemspec)
[![MIT license](https://img.shields.io/badge/License-MIT-blue)](LICENSE.txt)

[Website](https://ydah.github.io/merminal/) · [Gallery](https://ydah.github.io/merminal/gallery.html)

[Quick start](#quick-start) · [Features](#features) · [Diagram support](#diagram-support) · [Ruby API](#ruby-api) · [Development](#development)

</div>

Render Mermaid source directly in your terminal. `merminal` runs without Node.js, a browser, external processes, or runtime gem dependencies.

## Quick start

Install the [published gem](https://rubygems.org/gems/merminal) with Ruby 3.3 or newer:

```sh
gem install merminal
```

With Bundler, add `gem "merminal"` to your Gemfile.

Pipe a diagram into the CLI:

```sh
printf 'flowchart LR\n  A[Mermaid source] --> B[merminal]\n  B --> C[Terminal output]\n' | merminal
```

```text
   ┌──────────────────┐   ┌────────────┐   ┌───────────────────┐
   │  Mermaid source  ├──▶┤  merminal  ├──▶┤  Terminal output  │
   └──────────────────┘   └────────────┘   └───────────────────┘
```

## Features

- Render diagrams as Unicode or printable ASCII text, with four color themes.
- Read `.mmd` files, standard input, or Mermaid fences in Markdown.
- Check syntax and inspect line-numbered diagnostics for core diagram types.
- Use the CLI or the `Merminal` Ruby API.

## Usage

```sh
merminal diagram.mmd
merminal --ascii diagram.mmd
merminal --markdown notes.md
merminal --check --strict diagram.mmd
merminal --width 80 --theme solarized --color always diagram.mmd
```

Run `merminal --help` for all options. If a requested width cannot hold a diagram, the CLI reports the actual width and keeps the full drawing.

## Diagram support

`merminal` renders documented Mermaid syntax subsets with diagram-specific
terminal layouts. Browser-only directives have no terminal representation.
Browse the [syntax references](docs/syntax/README.md) or the [gallery](gallery.html).

## Ruby API

```ruby
require "merminal"

puts Merminal.render("flowchart LR\nA --> B")

document = Merminal.parse("pie\n\"A\" : 3\n\"B\" : 7")
warn document.diagnostics.map(&:to_s).join("\n")
puts document.render(charset: :ascii)
```

`Merminal.markdown_blocks` extracts Mermaid fences from Markdown.
`Merminal.register`, Scene primitives, and plugin interfaces are experimental.

## Limitations

- Pie charts show proportions as horizontal bars.
- Dense edge labels can cross lines; self loops use outside lanes.
- Unicode ambiguous width defaults to one cell. Set `ambiguous_width: 2` for
  terminals that use two; emoji width can vary across fonts.
- ASCII mode replaces non-ASCII labels with `?`.

## Development

```sh
bundle install
bundle exec rake spec
bundle exec rake gallery
```

See the [changelog](CHANGELOG.md) for releases and [architecture decisions](docs/adr/README.md) for contributor context.

## License

Released under the [MIT License](LICENSE.txt). This is an independent implementation of [Mermaid](https://mermaid.js.org/) syntax. Thanks to [termaid](https://github.com/fasouto/termaid), [mermaid-ascii](https://github.com/AlexanderGrooff/mermaid-ascii), and [beautiful-mermaid](https://github.com/lukilabs/beautiful-mermaid) for inspiration.
