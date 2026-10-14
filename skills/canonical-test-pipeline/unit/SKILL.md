---
name: canonical-unit-test
description: Verify one behavior or Action contract with deterministic valid, boundary, and isolated-invalid cases.
---
# Canonical Unit Test

## Goal
Check the contract of one function/Action without mixing in load, concurrency, fault injection, or security-boundary concerns.

## Required cases
- One fully valid synthetic input.
- Boundary values for each declared constraint.
- One invalid mutation at a time, with all unrelated inputs remaining valid.
- Deterministic seed and stable case names.

## Evidence
The runtime evaluates actual behavior and invariants. A compiler-generated plan is not a passing result. Keep payloads and business events ephemeral; persist only test identity, seed/config fingerprint, result status, duration, and sanitized failure evidence.
