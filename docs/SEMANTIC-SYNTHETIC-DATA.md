# Semantic synthetic data generation

The `src/synthetic.zig` module adds deterministic, type-aware candidate generation for the currently modeled value domains (integer, string, boolean).

## Extraction contract

A language adapter should inspect the target function/Action's AST and lower the following into `model.FunctionSpec` and `SemanticHints`:

1. **Types and constraints**: primitive/enum/optional/container types, integer bounds, string lengths, nullability and collection cardinality. The current core model supports string, signed 64-bit integer and boolean; richer types require explicit model variants and adapters.
2. **Logical tests**: branch comparisons, equality, inequalities, ranges, emptiness/null checks and pattern predicates. Preserve parameter-to-operand relationships rather than reducing predicates to text.
3. **Value transformers**: trim/case conversion/whitespace normalization, parsing, arithmetic, clamping, substring and replacement. Emit transform hints and operand values from the AST. Hints guide input selection; they do not execute the function or claim branch coverage.

## Optimization heuristic: Semantic Boundary + Stratified Coverage (SBSC)

For each parameter, spend the finite candidate budget in this order:

1. Exact minimum and maximum, then adjacent representable values.
2. Midpoint and equal-width strata spanning the full declared domain.
3. Constants found in predicates and transformer operands (e.g. `age == 42`, `amount > limit`, `trim(name)`).
4. Shape values for strings: empty, whitespace, mixed case, numeric-looking text, and lengths at boundaries/strata.
5. Seeded pseudo-random values only for remaining budget.

Deduplicate values while retaining the first provenance. Boolean domains are exhaustively enumerated. Invalid inputs should be produced by a separate mutation pass, changing exactly one parameter and preserving all other arguments as valid. For multi-parameter predicates, add pairwise/MC/DC combinations in a later extension; per-parameter candidates alone do not prove combinations or path coverage.

## Guarantees and limits

Generation is deterministic for a fixed spec, hints, options and seed. The budget and maximum string length bound memory. The algorithm prioritizes distinct semantic regions instead of uniform random sampling, which tends to miss narrow boundaries. It is not possible to guarantee every value of a huge or infinite domain with finite samples; the aim is domain partition coverage. AST extraction is language-adapter work and must be validated against the target language's parser/type checker. Candidate generation alone is not execution evidence.
