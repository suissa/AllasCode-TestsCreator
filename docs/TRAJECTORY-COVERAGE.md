# Trajectory Coverage Testing

Trajectory coverage tests every reachable branch of a behavior/workflow graph through its terminal outcome. This complements TestsCreator's existing per-Action valid, boundary, and invalid-input generation.

## Terminology
- **Trajectory**: ordered node/state sequence and the transitions between them.
- **Terminal trajectory**: a path that starts at the graph's declared start and reaches a terminal node.
- **Transition coverage**: whether each modeled edge is traversed by at least one generated path.
- **Uncovered transition**: an edge not exercised by any generated path from the start.
- **Bounded path generation**: finite enumeration in the presence of cycles.

## Contract
A graph contains named nodes, labeled directed edges, a start node, and explicit terminal nodes. Generation validates all edge endpoints, enumerates terminal trajectories deterministically, and reports edge coverage separately from the paths.

Default cycle behavior stops revisiting a node within a path. A cycle-closing edge skipped by the default simple-path policy remains uncovered and is reported explicitly; it is not falsely counted as executed. Dedicated bounded-loop test generation can cover it in a later iteration. `max_depth` provides an additional hard bound.

## Example
```text
START -> VALIDATE
             | valid   -> ACCEPTED [terminal]
             | invalid -> RECOVER
                            | retry -> VALIDATE
                            | abort -> REJECTED [terminal]
```

The test plan should contain paths for START → VALIDATE → ACCEPTED and START → VALIDATE → RECOVER → REJECTED. A retry loop is bounded and must not cause infinite enumeration. Depending on cycle policy, the loop itself may require dedicated bounded-loop tests.

## Limits
Structural path enumeration does not establish that guards are satisfiable or that a runtime implementation follows the model. Integrations should add guard/action contracts and execute each generated trajectory in an isolated test environment. Full simple-path enumeration can grow exponentially; production callers should set depth/path-count limits.
