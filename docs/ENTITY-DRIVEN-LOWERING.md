# Entity Driven Testing: canonical lowering

The Entity DSL is parsed into a runtime-neutral `Scenario`. The lowering layer then maps that scenario to the five canonical test families:

- `unit`
- `load`
- `stress`
- `chaos`
- `security`

Each lowered case preserves the entity, input values, Action calls and expectation expressions. The compiler does not execute Actions or decide whether an expectation passed.

## Contract boundary

`Run` describes an Action invocation; `EvidenceContract` carries the expectations that the runtime must evaluate. The runtime remains the authority for execution results and terminal pass/fail decisions.

The current lowering is intentionally a structural mapping, not an execution adapter. Test-family-specific controls (load repetitions, stress workers, chaos fault injection and security capabilities) should be supplied by the canonical test configuration layer rather than inferred from an expectation string.

## Example

```text
Entity: Person
Input cpf = 04864713901
Run validate(cpf)
Expect isTruth
```

This scenario lowers to five cases, one per canonical test family, while preserving `validate(cpf)` and `isTruth` unchanged.

## Validation

`zig build test` includes the parser and lowering unit-test targets. The lowering tests verify all five kinds, preservation of Action arguments and expectation expressions, and runtime-owned result authority.
