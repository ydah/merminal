# Additional Mermaid syntax diagrams

The parser recognizes the Mermaid syntax declarations below:

`journey`, `quadrantChart`, `requirementDiagram`, `usecaseDiagram`,
`usecase-beta`, `gitGraph`, `C4Context`, `C4Container`, `C4Component`,
`C4Dynamic`, `C4Deployment`, `zenuml`, `sankey-beta`, `block-beta`,
`packet-beta`, `kanban`, `architecture-beta`, `radar-beta`, `treemap-beta`,
`venn-beta`, `ishikawa-beta`, `wardley-beta`, `treeView`, `treeView-beta`,
`cynefin-beta`, `swimlane-beta`, `eventModeling`, `agentflow-beta`,
`railroad-ebnf-beta`, `railroad-abnf-beta`, `railroad-peg-beta`, and
`railroad-beta`.

Each declaration has a diagram-specific terminal layout. Relationship diagrams
use the shared layered routing engine where that matches their semantics;
journeys, quadrants, packets, Kanban boards, radar charts, treemaps, Venn
diagrams, Ishikawa causes, Wardley maps, swimlanes, and event models use their
own terminal geometry. Ishikawa cause indentation and Treemap hierarchy are
retained in the terminal layout.
Railroad declarations render grammar rules with distinct terminal
and non-terminal nodes. Mermaid directives that only affect browser layout or
SVG styling are ignored.

Kanban task metadata written as `@{ ... }` is shown with the task label. Wardley
maps support `component`, `anchor`, their `inertia` and source-strategy
decorators, links (including labels and reverse/dashed forms), `evolve`,
`pipeline`, `evolution`, trends,
positioned `note`, and numbered `annotation` statements. Event Modeling supports compact and relaxed time frames, reset
frames (reset frames retain an `rf` marker), `->>` relations, and named `data` blocks; UI/processor,
command/read model, and event aliases share their corresponding swimlanes.

Railroad rules end with `;`: EBNF uses `=` or `::=`, ABNF uses `=`, and PEG
uses `<-`. Quoted strings are terminal nodes, identifiers are non-terminal
nodes, and top-level `|` or `/` alternatives become separate paths. The IR
form (`railroad-beta`) accepts `terminal("text")`, `nonterminal("name")`,
`special("text")`, `sequence(...)`, `choice(...)`, `optional(...)`,
`zeroOrMore(...)`, and `oneOrMore(...)`. EBNF/PEG comments and ABNF trailing
comments are ignored.

An `agentflow-beta` flow with no nodes is rendered as a labeled terminal card;
it does not fall back to the generic additional-syntax renderer.

```mermaid
railroad-ebnf-beta
title "Letter"
letter = "a" | "b" ;
```

```mermaid
usecase-beta
actor User
User --> (Use system)
```

The core diagram types have dedicated syntax references in the neighboring
files. This page keeps the additional declaration names and terminal subset in
one place. Browser-only styling and interaction directives are intentionally
ignored because they have no terminal equivalent.
