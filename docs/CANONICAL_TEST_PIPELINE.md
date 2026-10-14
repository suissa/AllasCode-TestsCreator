# Canonical Test Pipeline

AllasCode-TestsCreator unifies deterministic contract-case generation with the PureCore semantic test compiler. The compiler translates a semantic declaration plus scenario configuration into a canonical JSON bundle; a runtime-owned executor performs tests and decides outcomes.

## Five canonical test types

| Kind | Schema | Primary purpose |
| --- | --- | --- |
| unit | `pcore.test.unit.v1` | Valid, boundary, and isolated-invalid contract behavior |
| load | `pcore.test.load.v1` | Bounded repetitions, replay stability, idempotent settlement |
| stress | `pcore.test.stress.v1` | Concurrent workers, duration, failure budget, scheduling fairness |
| chaos | `pcore.test.chaos.v1` | Controlled faults, recovery, resume, replay |
| security | `pcore.test.security.v1` | Capabilities, explicit denials, secret handling, terminal authority |

## Compile and test

```sh
zig fmt --check build.zig src
zig build test
zig build run
```

The sample DSL and config live in `src/declarations/purecore.pct` and `src/config/purecore.yaml`. The compiler validates the matching suite/agent/intent identity, presence of all five canonical kinds, recognized config keys, and positive load/stress limits.

## Trust boundaries

- DSL and YAML are data, not executable test code.
- Runtime observations are the only authority for pass/fail.
- Generated tests are ephemeral: do not persist payloads or business events.
- Security tests never export secrets.
- Chaos runs are isolated and bounded.
- Unit, load, stress, chaos, and security tests remain distinct schemas, even though one pipeline compiles them.
