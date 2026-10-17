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

Inputs currently support strings, signed integers, and booleans. Run arguments are symbolic input names, which keeps the scenario independent from the implementation language.

Expectation expressions remain opaque strings at this layer. This allows the semantic layer to grow without coupling the parser to a fixed assertion vocabulary. Examples include `isTruth`, `isFalse`, `equals(100)`, and future domain-specific predicates.

## Layering

Entity Driven Testing is the behavioral layer above the existing contract generator and trajectory machinery:

`Entity → Input → Run → Expect → semantic lowering → execution → evidence`

The contract generator remains responsible for valid, boundary, and isolated-invalid data. The trajectory executor remains responsible for executing generated paths and reporting runtime feedback. The Entity DSL provides the declarative behavioral specification that can later compose those capabilities.

The next layer should add semantic lowering for the canonical test types without allowing the DSL itself to become executable code.
