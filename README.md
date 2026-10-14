# AllasCode TestsCreator

Automatic deterministic test generation for AllasCode function/Action contracts and behavior trajectories.

TestsCreator generates:
- one fully valid synthetic case;
- boundary cases from declared constraints;
- isolated invalid cases, changing exactly one parameter/property at a time;
- reproducible values from a seed;
- trajectory tests that traverse modeled workflow branches to terminal outcomes;
- edge-coverage reports that identify transitions not exercised from the declared start;
- ephemeral test execution metadata so payloads and business events are never persisted.

The canonical implementation targets Zig 0.16 and is designed to consume AllasCode Semantic AtomicBehavior Type constraints.

## Run

```bash
zig build test
zig build run
```

## Unit/contract tests

For a function such as `CreateUser(name: String(min=1,max=80), age: Int(min=18,max=120))`, the generator creates valid, boundary, and isolated invalid cases. Every negative case keeps all other arguments valid.

## Trajectory coverage

The new structural path generator is in [src/trajectory.zig](src/trajectory.zig), with the skill contract in [skills/trajectory-coverage/SKILL.md](skills/trajectory-coverage/SKILL.md) and details in [docs/TRAJECTORY-COVERAGE.md](docs/TRAJECTORY-COVERAGE.md).

Given a directed graph with a declared start and explicit terminal states, it enumerates reachable terminal trajectories, handles cycles with a bounded policy, and reports uncovered edges. This is structural model-based path generation; guard satisfiability and runtime execution still require adapters.

See [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) for the existing generator pipeline.
