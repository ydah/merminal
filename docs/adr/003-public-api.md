# ADR 003: Public API boundary

- Status: Accepted
- Date: 2026-09-21

## Context

Applications need a stable way to parse and render diagrams. Scene primitives
and plugin protocols can change as diagram support grows.

## Decision

The intended stable v1.0 API is `render`, `parse`, `markdown_blocks`,
`diagram_types`, and the documented document results. `register`, Scene
primitives, and the plugin protocol remain experimental.

## Consequences

Applications can rely on the documented rendering API at v1.0. Advanced
extension points may change before then.
