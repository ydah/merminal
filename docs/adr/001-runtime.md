# ADR 001: Runtime baseline

- Status: Accepted
- Date: 2026-09-21

## Context

Terminal use should work in Ruby environments with limited package access. The
implementation uses current Ruby language features and its standard library.

## Decision

Require CRuby 3.3 or newer and keep runtime gem dependencies at zero.

## Consequences

Users install no additional runtime gems. The implementation stays small by
targeting one maintained Ruby baseline; other Ruby implementations are tested
as best effort.
