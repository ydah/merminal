# ADR-0004: Layered graph layout

## Situation

Flow, state, class, and ER diagrams need predictable node placement.

## Decision

Use DFS cycle reversal, longest path ranks, stable median sweeps, and rank bands.

## Reason

These steps are deterministic and work across the structural diagrams.

## Result

The layout favors clarity over browser Mermaid parity. Coordinate assignment can be refined independently.
