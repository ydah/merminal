# ADR 002: Partial parsing and diagnostics

- Status: Accepted
- Date: 2026-09-21

## Context

Core diagrams may contain unsupported statements. Rejecting the whole document
would hide parts that can still be rendered.

## Decision

Core parsers render recognized statements and return line-numbered diagnostics.
Strict mode raises when parsing reports an error.

## Consequences

Callers can choose best-effort rendering or validation. Syntax guides define
the supported subset.
