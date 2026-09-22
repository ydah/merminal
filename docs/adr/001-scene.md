# ADR 001: Shared scene renderer

- Status: Accepted
- Date: 2026-09-21

## Context

Every diagram needs the same terminal characters, colors, and width handling.
Rendering cells inside each diagram would duplicate that work.

## Decision

Layouts produce immutable Scene primitives. One rasterizer draws the scene in
Unicode or ASCII and applies shared output options.

## Consequences

Diagram layouts describe geometry; the rasterizer owns terminal-cell behavior.
