# Architecture

TestsCreator converts a function/Action contract into a deterministic, runner-neutral test plan.

## Pipeline

1. **Discover** — inspect function/Action signature and semantic type metadata.
2. **Contract** — normalize parameters, types, constraints and invariants into `FunctionSpec`.
3. **Generate** — create valid, boundary and invalid-isolation cases.
4. **Lower** — adapters translate the canonical plan to Zig/TypeScript/Go/Rust/Python/WASM test frameworks.
5. **Execute** — a sandbox/runner executes generated tests.
6. **Evidence** — retain only reproducibility metadata and failure evidence.

## Canonical unit rule

For each function:

- one completely valid synthetic payload;
- boundary cases for every declared constraint;
- one negative mutation at a time;
- all non-target fields remain valid;
- deterministic seed enables exact reproduction.

This is unit/contract generation, not chaos testing. Fault injection such as timeout, cancellation, duplicate delivery, reorder, storage/network failure and concurrency belongs to a separate chaos layer.

## Ephemeral execution invariant

Generated test executions are marked:

```
test = true
ephemeral = true
persist_payload = false
persist_events = false
```

Business stores must never treat synthetic test traffic as durable domain state.

## Semantic AtomicBehavior Types

The intended AllasCode integration is for a Semantic AtomicBehavior Type to expose its constraints/invariants once. TestsCreator consumes that same canonical contract, avoiding duplicated validation rules in hand-written tests.
