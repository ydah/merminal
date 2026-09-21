# ADR-0001: Runtime dependencies

## Situation

Terminal use should work in Ruby environments with limited package access.

## Decision

Keep runtime gem dependencies at zero.

## Reason

Ruby and its standard libraries cover parsing, dates, options, and terminal output.

## Result

Development tools remain optional and CI checks the gemspec.
