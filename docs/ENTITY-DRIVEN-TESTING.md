# Entity Driven Testing

The Entity Driven Testing DSL describes a test from the entity being exercised rather than from a test framework API.

The first vertical slice is intentionally small:

```text
Entity: Person
Input cpf = 04864713901
Run validate(cpf)
Expect isTruth
```

`Entity` identifies the domain subject. `Input` declares named data. `Run` names the Action to invoke and references inputs by name. `Expect` declares the semantic expectation.

The parser is deliberately runtime-neutral. It creates a structured scenario but does not execute `validate`, interpret `isTruth`, or decide pass/fail. Those responsibilities belong to the execution/validation layer.

## Data model

A parsed scenario contains:

- one entity;
- zero or more named inputs while parsing;
- one or more Action runs;
- one or more expectations.

Inputs currently support strings, signed integers, and booleans. Zero-padded numeric values such as `04864713901` remain strings so identifiers like CPF, postal codes, and account numbers are not corrupted by integer parsing. Run arguments must reference declared input names; duplicate input declarations and unknown references are rejected before lowering.

Expectation expressions remain opaque strings at this layer. This allows the semantic layer to grow without coupling the parser to a fixed assertion vocabulary. Examples include `isTruth`, `isFalse`, `equals(100)`, and future domain-specific predicates.

## Layering

Entity Driven Testing is the behavioral layer above the existing contract generator and trajectory machinery:

`Entity → Input → Run → Expect → semantic lowering → execution → evidence`

The contract generator remains responsible for valid, boundary, and isolated-invalid data. The trajectory executor remains responsible for executing generated paths and reporting runtime feedback. The Entity DSL provides the declarative behavioral specification that can later compose those capabilities.

The lowering layer maps the parsed scenario to the five canonical test families: unit, load, stress, chaos, and security. It preserves inputs, Action calls, and expectation expressions without executing them. Next, each family needs its own execution policy and evidence contract, while the runtime remains the authority for pass/fail.
