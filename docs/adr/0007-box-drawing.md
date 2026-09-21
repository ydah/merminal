# ADR-0007: Box drawing table

## Situation

Joined lines need Unicode characters for mixed arm weights.

## Decision

Generate the arm mapping from UnicodeData.txt and bundle the table.

## Reason

Unicode character names encode arm directions and weights more completely than a manual table.

## Result

Regenerate from Unicode 17.0 source files when Unicode support is updated.
