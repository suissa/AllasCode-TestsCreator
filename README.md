# AllasCode TestsCreator

Deterministic, runner-neutral test generation, canonical semantic compilation, trajectory coverage, and Zig-native contract-aware fuzzing for AllasCode Actions and AtomicBehaviors.

TestsCreator generates:
- one fully valid synthetic case;
- boundary cases from declared constraints;
- isolated invalid cases, changing exactly one parameter/property at a time;
- reproducible values from a seed;
- trajectory tests that traverse modeled workflow branches to terminal outcomes;
- edge-coverage reports that identify transitions not exercised from the declared start;
- ephemeral test execution metadata so payloads and business events are never persisted.

1. **Contract-case generation** — one valid synthetic case, boundary cases, and isolated invalid cases derived from declared constraints, using a reproducible seed.
2. **Semantic suite compilation** — the PureCore DSL and scenario config compile into deterministic canonical JSON for five distinct test types: unit, load, stress, chaos, and security.

The semantic compiler validates matching suite/agent/intent identities, required test kinds, recognized configuration keys, and bounded non-zero load/stress settings. DSL/config are data, never executable assertions. The runtime executor remains the authority for observed pass/fail outcomes.

## Canonical test types

## Unit/contract tests

For a function such as `CreateUser(name: String(min=1,max=80), age: Int(min=18,max=120))`, the generator creates valid, boundary, and isolated invalid cases. Every negative case keeps all other arguments valid.

## Trajectory coverage

The structural path generator is in [src/trajectory.zig](src/trajectory.zig), with its skill contract in [skills/trajectory-coverage/SKILL.md](skills/trajectory-coverage/SKILL.md) and specification in [docs/TRAJECTORY-COVERAGE.md](docs/TRAJECTORY-COVERAGE.md).

Given a directed graph with a declared start and explicit terminal states, it enumerates reachable terminal trajectories, bounds traversal, and reports transitions not represented in emitted paths. This is structural model-based path generation; guard satisfiability and runtime execution still require adapters.

## Native Smith semantic fuzzing

The contract-aware adapter in [src/smith_fuzz.zig](src/smith_fuzz.zig) uses Zig 0.16 `std.testing.Smith` rather than a parallel evolutionary engine. It biases typed values toward declared boundaries, bounds string allocation, and fuzzes the canonical case generator.

```sh
zig build test
zig build test-fuzz
```

Specification: [docs/NATIVE-SMITH-SEMANTIC-FUZZING.md](docs/NATIVE-SMITH-SEMANTIC-FUZZING.md). Skill: [skills/native-smith-semantic-fuzzing/SKILL.md](skills/native-smith-semantic-fuzzing/SKILL.md). Runtime Action execution and trajectory/invariant feedback remain future adapter work.

## Canonical sources and skills

Given a directed graph with a declared start and explicit terminal states, it enumerates reachable terminal trajectories, handles cycles with a bounded policy, and reports uncovered edges. This is structural model-based path generation; guard satisfiability and runtime execution still require adapters.

See [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) for the existing generator pipeline.
