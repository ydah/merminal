# ADR-0011: Timeline layout

## Situation

The design allows period columns or a vertical time axis. The terminal needs to keep long event labels readable at narrow widths.

## Options

- Period columns make chronology visible across the screen, but each additional period consumes horizontal space and wraps event text.
- A vertical list grows downward and leaves the full row width for each event. Repeated periods remain explicit.

## Decision

Use the vertical list shown by the timeline fixtures in the gallery. Preserve source order within each section.

## Result

Wide timelines are easier to scan without a target width. A column layout can be added if a later use case needs side by side periods.
