# ADR-0012: Public API boundary

## Situation

The documented render and parse calls need a stable contract. Scene primitives and plugin parsing methods expose layout internals that may change as more syntax is supported.

## Decision

The intended stable v1.0 API is `MermaidTerm.render`, `.parse`, `.markdown_blocks`, `.diagram_types`, `.register`, and the keyword arguments and return types shown in the design's §6.14. `Document#type`, `#diagnostics`, `#render`, and `MarkdownBlock#line` and `#render` are part of it.

Keep `Document#scene`, Scene primitives, and the plugin interface experimental at v1.0. Their names are available for advanced use, but their shape may change in later minor versions.

## Result

RBS describes the stable calls. The README identifies the experimental extension points so callers can choose their dependency on internals.
