# ADR-0008: Parser diagnostics

## Situation

Real Mermaid files may contain unsupported statements.

## Decision

Collect line numbered diagnostics and render recognized statements. Raise in strict mode.

## Reason

This keeps partial diagrams useful while supporting CI lint checks.

## Result

Each syntax document defines the accepted subset.
