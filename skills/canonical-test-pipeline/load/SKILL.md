---
name: canonical-load-test
description: Verify bounded repeated execution, replay stability, and idempotent settlement under configured load.
---
# Canonical Load Test

## Goal
Verify behavior across repeated events and bounded volumes, without treating this as a concurrency stress or fault-injection test.

## Required checks
- Positive bounded repetition count and event ceiling.
- Duplicate/replayed input settles idempotently.
- Repeated runs preserve expected results and invariants.
- Runtime reports errors and resource limits honestly.

## Evidence
Record repetitions, event counts, timings, seed/config fingerprint, and sanitized failure details. Do not persist synthetic payloads or business events.
