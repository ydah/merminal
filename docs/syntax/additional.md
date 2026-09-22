# Additional Mermaid diagrams

These diagram declarations have dedicated terminal layouts. Browser-only
styling and interaction directives are not rendered.

- **Journey and requirements:** `journey`, `quadrantChart`,
  `requirementDiagram`, `usecaseDiagram`, `usecase-beta`.
- **Git and C4:** `gitGraph`, `C4Context`, `C4Container`, `C4Component`,
  `C4Dynamic`, `C4Deployment`.
- **Charts and maps:** `sankey-beta`, `radar-beta`, `treemap-beta`,
  `venn-beta`, `ishikawa-beta`, `wardley-beta`.
- **Boards and structures:** `block-beta`, `packet-beta`, `kanban`,
  `architecture-beta`, `treeView`, `treeView-beta`, `cynefin-beta`.
- **Modeling:** `zenuml`, `swimlane-beta`, `eventModeling`,
  `agentflow-beta`.
- **Railroad grammars:** `railroad-ebnf-beta`, `railroad-abnf-beta`,
  `railroad-peg-beta`, `railroad-beta`.

Aliases `gitgraph`, `block`, `packet`, `treeview`, `treeview-beta`,
`eventmodeling`, and `agentflow` are also recognized.

Some syntax highlights:

- **Wardley maps:** components, anchors, inertia and source-strategy decorators,
  links, `evolve`, `pipeline`, `evolution`, notes, and annotations.
- **Event Modeling:** `tf` / `timeframe` and `rf` / `resetframe` entries,
  `->>` relations, and `data` blocks.
- **Kanban:** task labels and `@{ ... }` metadata.
- **Railroad:** EBNF rules use `=` or `::=`; ABNF uses `=`; PEG uses `<-`.
  Quoted strings are terminals, identifiers are non-terminals, and alternatives
  use `|` or `/`. Comments are ignored. `railroad-beta` also accepts
  `terminal(...)`, `nonterminal(...)`, `special(...)`, `sequence(...)`,
  `choice(...)`, `optional(...)`, `zeroOrMore(...)`, and `oneOrMore(...)`.

```mermaid
railroad-ebnf-beta
letter = "a" | "b" ;
```
