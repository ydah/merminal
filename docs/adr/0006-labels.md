# ADR-0006: Edge labels

## Situation

Labels need space near routed edges.

## Decision

Place a sized label node at the middle rank of each labeled edge. The edge passes beside its text. Self loop labels use the next free row or column beside their outside route.

## Reason

Including the label in ordering reserves space before routing.

## Result

Dense crossings can still reduce legibility.
