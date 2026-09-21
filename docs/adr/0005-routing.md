# ADR-0005: Edge routing

## Situation

Edges should avoid boxes in layered diagrams.

## Decision

Route adjacent rank edges through rank channels and long or cyclic edges outside node bands.
Route an edge below subgraph frames when neither endpoint belongs to a frame it would cross.

## Reason

This uses the rank structure and avoids a general grid search.

## Result

Dense channels can be wide; gallery review guides spacing changes.
