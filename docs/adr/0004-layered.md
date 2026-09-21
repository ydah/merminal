# ADR-0004: Layered graph layout

## Situation

Flow, state, class, and ER diagrams need predictable node placement.

## Decision

Use DFS cycle reversal and longest path ranks. Double the minimum rank span of labeled edges, then insert a dummy in each skipped rank and a sized label node at the middle rank. Order the resulting adjacent-rank segments with up to eight alternating median sweeps. Count crossings with a Fenwick tree after each sweep and keep the best order. Give dummies priority when aligning long edges.
Keep nested subgraph members together during sweeps and give top-level groups separate order-axis bands across ranks.

## Reason

These steps are deterministic and work across the structural diagrams.

## Result

Long edges now use rank channels. Self loops still use outside lanes. Priority alignment is limited to diagrams without subgraphs so that cluster bands remain intact.
