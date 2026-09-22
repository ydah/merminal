# ADR 002: Scene layer

- Status: Accepted
- Date: 2026-09-21

## Context

Diagram layout should not choose terminal border characters. Letting each
diagram plugin render terminal cells would duplicate rasterization behavior.

## Decision

Pass immutable geometric Scene primitives to one shared rasterizer.

## Consequences

All diagrams share line joining, themes, width fitting, and ASCII fallback.
Plugins remain independent of terminal cell representation.
