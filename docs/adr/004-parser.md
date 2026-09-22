# ADR 004: Parser diagnostics

- Status: Accepted
- Date: 2026-09-21

## Context

Real Mermaid files may contain unsupported statements. Rejecting an entire
document would hide the parts that can still be rendered.

## Decision

Collect line-numbered diagnostics and render recognized statements. Raise in
strict mode so callers can choose partial or validated parsing.

## Consequences

Partial diagrams remain useful while CI can enforce strict parsing. Syntax
reference documents define the accepted subset.
