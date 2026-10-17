# Validation-Driven Synthetic Data Generation

Validation-Driven Synthetic Data Generation (VDSDG) is a contract-aware generation pattern in which declared constraints and structured validator feedback guide candidate creation and repair. It combines constraint-based data generation with a validation feedback loop; when mutations are guided by runtime feedback, it overlaps with feedback-directed generation/fuzzing.

## Why it exists

A generic random or Faker-style generator can produce volume without producing useful coverage. TestsCreator should use the same property/type metadata as the implementation: types, constraints, normalization rules, and invariants. Validator outcomes then explain which condition a candidate violated and what targeted mutation is worth trying next.

## Feedback loop

1. **Read the contract.** Normalize each parameter's type, bounds, normalizer, and invariants from the canonical property/AtomicBehavior contract.
2. **Create a deterministic candidate.** Use a seed and declared constraints to make a reproducible initial value.
3. **Validate in an isolated runner.** Execute the real validator/Action adapter; do not infer success from generated shape alone.
4. **Return structured feedback.** Prefer stable codes and fields over free-form exception parsing: code, parameter, expected, actual, optional invariant, and a repair hint.
5. **Apply a targeted mutation.** Change the failing field or invariant-relevant subset only. Preserve other valid fields to keep the experiment attributable.
6. **Revalidate and classify.** Keep the original failing input as negative evidence. Store repaired passing candidates as nominal examples; keep one-constraint failures as precise negative/edge examples.
7. **Bound the search.** Use deterministic seeds, mutation budgets, allocation/time limits, cycle detection, and a maximum number of attempts. If feedback repeats or constraints conflict, stop with a diagnostic rather than looping.
8. **Emit reproducible evidence.** Record seed, case ID, violated rule, mutation operation, validator code, and outcome. Do not persist payloads or business events by default.

## Valid and invalid data are both first-class

- **Nominal cases:** satisfy the declared contract and pass the authoritative validator.
- **Boundary cases:** sit exactly on or immediately around a constraint boundary.
- **Isolated negative cases:** violate one target rule while other fields remain valid.
- **Feedback-derived candidates:** are new candidates created in response to a specific validator result; the original failure remains in the corpus.
- **Unresolved cases:** are reported when no safe repair is known, the feedback is ambiguous, or a bounded attempt budget is exhausted.

A repair is not proof of validity. The real validator remains the oracle. Likewise, passing property constraints does not prove a business invariant unless that invariant is actually evaluated by its authoritative adapter.

## Error contract for the forger

A useful validator error should be both human-readable and machine-actionable. The initial implementation in src/validation_feedback.zig defines stable violation codes (below_min, above_max, too_short, too_long, wrong_type, invariant_failed, normalization_failed), structured diagnostic fields, deterministic integer clamping, and string length repair. These helpers are deliberately limited: padding with x repairs length only, not semantic content. Domain-specific validators must register suitable repair strategies rather than letting the forger guess.

Example diagnostic:

```text
VALIDATION_FEEDBACK code=below_min parameter=age expected=integer >= 18 actual=12 action=apply_targeted_repair_then_revalidate
```

Adapters should expose codes and metadata directly as a typed result where possible. Parsing human prose is a compatibility fallback, not the canonical interface.

## Safety and reproducibility

- Keep generated cases ephemeral: test=true, ephemeral=true, persist_payload=false, persist_events=false.
- Run validators in a sandbox with no production side effects or secrets.
- Redact sensitive values from logs; diagnostics should normally report type, length, range, and a stable hash/reference rather than raw credentials or PII.
- Keep the original failing candidate and its repair lineage in the test report, but do not persist business payloads.
- Separate deterministic contract generation from coverage-guided fuzzing. Zig's native Smith can supply mutations; TestsCreator owns the contract mapping and interpretation of structured feedback.

## Current scope and next integration boundary

The new module provides diagnostics and deterministic repairs for numeric bounds and string lengths, with tests. It does not yet invoke arbitrary validators, introspect arbitrary error objects, optimize a corpus using coverage signals, or claim that a repaired value passes a real Action. The next integration is an execution adapter that maps authoritative validator results to Diagnostic, feeds them into a bounded mutation loop, and records only reproducibility metadata and outcome evidence.
