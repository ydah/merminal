# ADR 003: Structural diagram layout

- Status: Accepted
- Date: 2026-09-21

## Context

Flow, state, class, and ER diagrams need predictable placement and routing. A
shared layout model avoids a separate strategy for each structural diagram.

## Decision

Use a deterministic layered layout with rank channels. Reserve space for long
edges and labels before routing, keep nested subgraphs together, and route loops
through outside lanes.

## Consequences

Structural diagrams share predictable placement and routing. The exact sweep,
crossing, and rasterization algorithms remain implementation details.
