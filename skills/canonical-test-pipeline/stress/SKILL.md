---
name: canonical-stress-test
description: Verify bounded concurrent workers, duration, failure budget, and scheduling fairness.
---
# Canonical Stress Test

## Goal
Expose race conditions, starvation, resource exhaustion, and unfair scheduling under a declared workload.

## Required checks
- Explicit positive worker count and duration.
- Bounded workload and configured failure budget.
- Fair scheduling and bounded memory invariants.
- Capture latency/throughput and resource signals where the executor supports them.

## Safety
Use isolated test resources. Do not target production systems without explicit authorization. Runtime observations, not the configuration, determine pass/fail.
