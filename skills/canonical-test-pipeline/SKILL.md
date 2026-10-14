---
name: canonical-test-pipeline
description: Compile AllasCode semantic test declarations and scenario configuration into deterministic canonical test contracts.
---

# Canonical Test Pipeline

## Purpose
Use this skill when an AtomicBehavior, Action, agent, or pipeline stage needs canonical verification. The semantic declaration describes the scenario; configuration provides bounded parameters. Neither file is executable test code and neither may decide the observed result.

## Workflow
1. Identify the behavior/Action contract, inputs, constraints, invariants, capabilities, and terminal authority.
2. Declare one or more scenarios in `src/declarations/purecore.pct` using only supported test kinds.
3. Put limits, fault plans, capabilities, and explicit denials in `src/config/purecore.yaml`.
4. Keep suite, agent, and intent identity identical across both files.
5. Compile through `src/semantic_compiler.zig`; treat missing canonical kinds, identity mismatches, unknown config keys, and invalid numeric bounds as build failures.
6. Validate generated JSON and hand it to the runtime-owned executor.
7. Record reproducibility metadata and sanitized failure evidence only. Do not persist synthetic payloads or business events.
8. Never mark a test passed based on the declaration/configuration alone. Only runtime observations determine the outcome.

## Canonical test skills
- `skills/canonical-test-pipeline/unit/SKILL.md`
- `skills/canonical-test-pipeline/load/SKILL.md`
- `skills/canonical-test-pipeline/stress/SKILL.md`
- `skills/canonical-test-pipeline/chaos/SKILL.md`
- `skills/canonical-test-pipeline/security/SKILL.md`

## Invariants
- Deterministic inputs and reproducible seeds/configuration.
- Bounded work, memory, duration, and output.
- Negative tests mutate one target constraint at a time.
- Fault injection is isolated from ordinary contract generation.
- Security denials are explicit; secrets are never exported.
- Test traffic is ephemeral: `test=true`, `ephemeral=true`, `persist_payload=false`, `persist_events=false`.
