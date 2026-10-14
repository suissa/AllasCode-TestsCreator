# AllasCode TestsCreator

Deterministic, runner-neutral test generation and canonical semantic test compilation for AllasCode Actions and AtomicBehaviors.

## Canonical pipeline

TestsCreator unifies two layers:

1. **Contract-case generation** — one valid synthetic case, boundary cases, and isolated invalid cases derived from declared constraints, using a reproducible seed.
2. **Semantic suite compilation** — the PureCore DSL and scenario config compile into deterministic canonical JSON for five distinct test types: unit, load, stress, chaos, and security.

The semantic compiler validates matching suite/agent/intent identities, required test kinds, recognized configuration keys, and bounded non-zero load/stress settings. DSL/config are data, never executable assertions. The runtime executor remains the authority for observed pass/fail outcomes.

## Canonical test types

| Kind | Purpose | Schema |
| --- | --- | --- |
| Unit | Valid, boundary, isolated-invalid contract behavior | `pcore.test.unit.v1` |
| Load | Bounded repetitions, idempotent settlement, replay stability | `pcore.test.load.v1` |
| Stress | Concurrent workers, duration, failure budget, fair scheduling | `pcore.test.stress.v1` |
| Chaos | Controlled faults, recovery, resume and replay | `pcore.test.chaos.v1` |
| Security | Capability allowlist, denials, secret handling, terminal authority | `pcore.test.security.v1` |

## Run

Requires Zig 0.16.

```sh
zig fmt --check build.zig src
zig build test
zig build run
```

## Canonical sources and skills

- Semantic declaration: [src/declarations/purecore.pct](src/declarations/purecore.pct)
- Scenario configuration: [src/config/purecore.yaml](src/config/purecore.yaml)
- Compile-time compiler: [src/semantic_compiler.zig](src/semantic_compiler.zig)
- Pipeline specification: [docs/CANONICAL_TEST_PIPELINE.md](docs/CANONICAL_TEST_PIPELINE.md)
- Pipeline skill: [skills/canonical-test-pipeline/SKILL.md](skills/canonical-test-pipeline/SKILL.md)
- Skills for [unit](skills/canonical-test-pipeline/unit/SKILL.md), [load](skills/canonical-test-pipeline/load/SKILL.md), [stress](skills/canonical-test-pipeline/stress/SKILL.md), [chaos](skills/canonical-test-pipeline/chaos/SKILL.md), and [security](skills/canonical-test-pipeline/security/SKILL.md).

The generator's ephemeral policy remains mandatory: `test=true`, `ephemeral=true`, `persist_payload=false`, `persist_events=false`. Never persist generated payloads or synthetic business events. Fault injection must be isolated and bounded.
