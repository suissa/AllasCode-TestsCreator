---
name: canonical-security-test
description: Verify capability allowlists, explicit denials, secret handling, and runtime-owned terminal authority.
---
# Canonical Security Test

## Goal
Verify that an Action can use only its granted capabilities and cannot bypass the runtime's authority.

## Required checks
- Enumerate allowed capabilities and explicit denied operations.
- Probe denied network, arbitrary-code, source-mutation, and direct-terminal paths as applicable.
- Ensure secrets and sensitive payloads never enter generated artifacts or telemetry.
- Ensure the runtime alone determines terminal pass/fail state.

## Evidence
Store sanitized denial/rejection evidence and policy/config fingerprints. Never export secrets or persist synthetic business payloads.
