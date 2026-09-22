# ADR 005: Public API boundary

- Status: Accepted
- Date: 2026-09-21

## Context

The documented render and parse calls need a stable contract. Scene primitives
and plugin parsing methods expose layout internals that may change as more
syntax is supported.

## Decision

The intended stable v1.0 API is the render, parse, Markdown extraction, diagram
registration, and diagram type calls documented in the README and RBS. Their
document and block result fields are stable as documented.

Keep `Document#scene`, Scene primitives, and the plugin interface experimental at v1.0. Their names are available for advanced use, but their shape may change in later minor versions.

## Consequences

RBS describes the stable calls. Scene primitives and plugin interfaces remain
experimental extension points.
