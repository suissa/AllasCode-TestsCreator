# Semantic Invariant AST (TypeScript starter)

This prototype implements the narrow AST role used by AllasCode-TestsCreator: correlate nominal/brand types with their primitive type and with the primitive's invariant expressions.

It is **not** a source-code parser and it does **not** decide whether a candidate is valid. It represents and evaluates logical decisions, calculations, comparisons, and references. The authoritative `process`/validator remains responsible for accepting, rejecting, or self-healing candidate values.

## Model

```text
Nominal type / Brand
  └── Primitive kind
       └── Invariant expression nodes
            ├── logical decisions: and / or / not
            ├── calculations: add / subtract / multiply / divide / remainder
            ├── comparisons: eq / neq / gt / gte / lt / lte
            ├── references to other nominal values
            └── derived values: string length
```

The AST builder creates reverse indexes by primitive, nominal type, and invariant. This allows the generator to find every invariant associated with a nominal type or its primitive without embedding validation policy into the generator.

An invariant evaluates to one of three practical outcomes:
- expression evaluated to `true`;
- expression evaluated to `false`;
- expression could not be evaluated (wrong operand type, missing reference, division by zero, or non-boolean invariant result).

A false invariant result is an observation, not a final business verdict. The runtime's authoritative process still determines the outcome.

## Example

```ts
const ast = new SemanticAstBuilder()
  .addType({
    kind: "nominal-type",
    id: "PersonAge",
    name: "PersonAge",
    primitive: "number",
    brand: "PersonAge",
  })
  .addInvariant({
    kind: "invariant",
    id: "PersonAge.minimum",
    ownerTypeId: "PersonAge",
    primitive: "number",
    expression: {
      kind: "comparison",
      operator: "gte",
      left: { kind: "self" },
      right: { kind: "literal", value: 0, primitive: "number" },
    },
  })
  .build();
```

## Run

Requires Node.js 20 or newer.

```sh
npm install
npm run typecheck
npm test
```

The package is intentionally isolated under `prototypes/` because the canonical generator and CI remain Zig-first. It is a starting point for defining the semantic graph before connecting it to the existing PureCore compiler, contract generator, and Smith fuzzing adapter.

## Type-casting graph

`TypeCastingGraph` represents primitive-to-primitive candidate conversions as directed edges. Each edge records its source/target primitive, risk classification, description, and conversion function. `pathsFrom(source, maxDepth)` enumerates simple paths without cycles up to a bound.

`explore(ast, nominalTypeId, value, { accept })` applies each candidate path while preserving the nominal type declaration, then calls the supplied authoritative process/validator for every successful conversion. A cast edge only means that a candidate can be produced; it never means the value is accepted. Rejected candidates remain useful evidence for fuzzing.

Example:

```ts
const graph = createDefaultCastingGraph();
const explored = await graph.explore(ast, "PersonAge", 21, {
  maxDepth: 2,
  accept: (candidate, context) => process(candidate, {
    nominalTypeId: context.nominalTypeId,
    inferredPrimitive: context.targetPrimitive,
  }),
});
```

The default graph is intentionally a starter, not a complete JavaScript/TypeScript conversion specification. Add edges for the exact casts your runtime supports. The declared nominal type remains unchanged even when a candidate follows several primitive conversions.
