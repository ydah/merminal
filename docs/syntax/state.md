# State syntax

`stateDiagram` and `stateDiagram-v2` accept `A --> B`, transition labels after `:`, `[*]` start and end, `state "Label" as ID`, `state ID <<choice>>`, `<<fork>>`, `<<join>>`, and `state ID { ... }` composite frames. `direction` accepts flowchart directions. `note left of ID` and `note right of ID` accept inline text after `:` or a block ending in `end note`.
