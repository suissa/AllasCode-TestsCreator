---
name: trajectory-coverage
description: Generate and assess tests that traverse workflow branches from an initial state to terminal outcomes. Use for state machines, workflows, agent behavior graphs, and control-flow contracts.
---

# Trajectory Coverage Skill

## Purpose
Validate complete modeled trajectories, not just isolated functions or individual transitions. Generate one test path for each reachable terminal outcome while reporting transitions that cannot be covered from the declared start state.

## Inputs
- Directed behavior graph: nodes/states and labeled edges/transitions.
- Exactly one declared start node.
- Explicit terminal nodes.
- Optional maximum path depth and cycle policy.
- Optional guards and action contracts supplied by a future adapter.

## Procedure
1. Validate the start node, edge endpoints, and traversal bounds.
2. Enumerate paths from the start node.
3. Stop and emit a trajectory when a terminal node is reached.
4. Handle cycles deterministically: by default do not revisit a node on the same path; use explicit bounds for loop testing.
5. Record covered transitions and report uncovered transitions separately.
6. Produce a test case for each terminal trajectory, preserving ordered nodes and transitions.
7. Execute through a runner adapter and compare observed outcomes against the path contract.
8. Store only test metadata and failure evidence; synthetic payloads and domain events remain ephemeral.

## Acceptance criteria
- Every emitted terminal trajectory begins at the declared start and ends at a terminal node.
- Each path's edge order matches its node order.
- All reachable terminal branches are represented.
- Unreachable or uncovered edges are explicitly reported; never claim full coverage if any remain.
- Cycles cannot cause unbounded generation.
- Invalid graph references and invalid limits fail explicitly.
- Results are deterministic for the same graph and options.

## Scope
The current implementation enumerates structural paths and measures edge coverage. It does not execute business actions, evaluate guards, prove semantic feasibility, or guarantee exhaustive path coverage for arbitrary cyclic graphs. Those require graph adapters, guard evaluation, bounded-loop policies, and runner integration.
