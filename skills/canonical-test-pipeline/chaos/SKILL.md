---
name: canonical-chaos-test
description: Inject declared faults and verify recovery, resume, and deterministic replay.
---
# Canonical Chaos Test

## Goal
Test recovery from controlled interruption and infrastructure faults; this is separate from unit and load testing.

## Required checks
- Explicit allowlisted fault set and bounded injection window.
- Declared recovery strategy.
- Restart/resume/replay behavior and no duplicate durable effects.
- Capture fault timeline and recovery evidence.

## Safety
Faults must run in an isolated, disposable environment with bounded blast radius. Never infer successful recovery from a configured recovery name; verify observed post-fault state.
