# ADR-0003: Scene layer

## Situation

Diagram layout should not choose terminal border characters.

## Decision

Pass immutable geometric Scene primitives to one rasterizer.

## Reason

Line joining and ASCII fallback are then shared by every diagram.

## Result

Diagram plugin code contains no box drawing literals.
