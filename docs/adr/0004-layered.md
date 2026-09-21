# ADR-0004: Layered graph layout

## Situation

Flow, state, class, and ER diagrams need predictable node placement.

## Decision

Use DFS cycle reversal, longest path ranks, and up to eight alternating median sweeps. Count adjacent-rank crossings with a Fenwick tree after each sweep and keep the best order. Place nodes in rank bands.

## Reason

These steps are deterministic and work across the structural diagrams.

## Result

The layout favors clarity over browser Mermaid parity. Long edges still use outside lanes; dummy-node normalization and priority coordinate assignment remain future layout work.
