# ADR-0006: Edge labels

## Situation

Labels need space near routed edges.

## Decision

Place labels next to the corresponding edge track. Track allocation reserves their display width, and placement moves a label to the next free row or column when another label or node occupies its first position.

## Reason

The channel already reserves track rows and keeps labels outside node boxes.

## Result

Dense crossings can still reduce legibility. The design's normalized label nodes remain a layout upgrade before v1.0.
