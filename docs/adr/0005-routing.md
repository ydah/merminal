# ADR-0005: Edge routing

## Situation

Edges should avoid boxes in layered diagrams.

## Decision

Route normalized edge segments through channels between adjacent ranks. Use outside lanes for self loops.
Route an edge below subgraph frames when neither endpoint belongs to a frame it would cross.

## Reason

This uses the rank structure and avoids a general grid search.

## Result

Dense channels can make a diagram wide.
