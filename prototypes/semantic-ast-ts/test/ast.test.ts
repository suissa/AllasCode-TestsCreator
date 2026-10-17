import assert from "node:assert/strict";
import test from "node:test";
import {
  SemanticAstBuilder,
  evaluateInvariant,
  invariantsForType,
  primitiveForType,
  type Invariant,
  type NominalType,
} from "../src/index.js";

const age: NominalType = {
  kind: "nominal-type",
  id: "PersonAge",
  name: "PersonAge",
  primitive: "number",
  brand: "PersonAge",
};

const isAdult: Invariant = {
  kind: "invariant",
  id: "age.is-adult",
  ownerTypeId: "PersonAge",
  primitive: "number",
  expression: {
    kind: "comparison",
    operator: "gte",
    left: { kind: "self" },
    right: { kind: "literal", value: 18, primitive: "number" },
  },
};

function fixture() {
  return new SemanticAstBuilder()
    .addType(age)
    .addInvariant(isAdult)
    .build();
}

test("correlates nominal type to its primitive and invariants", () => {
  const ast = fixture();
  assert.equal(primitiveForType(ast, "PersonAge"), "number");
  assert.deepEqual(
    invariantsForType(ast, "PersonAge").map((invariant) => invariant.id),
    ["age.is-adult"],
  );
  assert.deepEqual(ast.typesByPrimitive.get("number"), ["PersonAge"]);
  assert.deepEqual(ast.invariantsByPrimitive.get("number"), ["age.is-adult"]);
});

test("evaluates comparisons without treating evaluation as validation", () => {
  const ast = fixture();
  assert.deepEqual(evaluateInvariant(ast, "age.is-adult", 18), {
    invariantId: "age.is-adult",
    ownerTypeId: "PersonAge",
    ok: true,
    value: true,
  });
  assert.deepEqual(evaluateInvariant(ast, "age.is-adult", 12), {
    invariantId: "age.is-adult",
    ownerTypeId: "PersonAge",
    ok: true,
    value: false,
  });
  assert.equal(evaluateInvariant(ast, "age.is-adult", "not-a-number").ok, false);
});

test("supports calculations, comparisons, and logical decisions", () => {
  const ast = new SemanticAstBuilder()
    .addType(age)
    .addInvariant({
      kind: "invariant",
      id: "age.in-range",
      ownerTypeId: "PersonAge",
      primitive: "number",
      expression: {
        kind: "logical",
        operator: "and",
        operands: [
          {
            kind: "comparison",
            operator: "gte",
            left: { kind: "self" },
            right: { kind: "literal", value: 0, primitive: "number" },
          },
          {
            kind: "comparison",
            operator: "lte",
            left: {
              kind: "calculation",
              operator: "add",
              left: { kind: "self" },
              right: { kind: "literal", value: 1, primitive: "number" },
            },
            right: { kind: "literal", value: 120, primitive: "number" },
          },
        ],
      },
    } satisfies Invariant)
    .build();

  assert.equal(evaluateInvariant(ast, "age.in-range", 119).value, true);
  assert.equal(evaluateInvariant(ast, "age.in-range", 120).value, false);
});

test("resolves references to other nominal types", () => {
  const name: NominalType = {
    kind: "nominal-type",
    id: "PersonName",
    name: "PersonName",
    primitive: "string",
    brand: "PersonName",
  };
  const ast = new SemanticAstBuilder()
    .addType(age)
    .addType(name)
    .addInvariant({
      kind: "invariant",
      id: "name.non-empty",
      ownerTypeId: "PersonName",
      primitive: "string",
      expression: {
        kind: "comparison",
        operator: "gt",
        left: {
          kind: "string-length",
          value: { kind: "self" },
        },
        right: { kind: "literal", value: 0, primitive: "number" },
      },
    })
    .addInvariant({
      kind: "invariant",
      id: "age.matches-reference",
      ownerTypeId: "PersonAge",
      primitive: "number",
      expression: {
        kind: "comparison",
        operator: "eq",
        left: { kind: "self" },
        right: { kind: "reference", typeId: "PersonAge" },
      },
    })
    .build();

  assert.equal(evaluateInvariant(ast, "name.non-empty", "Ada").value, true);
  assert.equal(
    evaluateInvariant(ast, "age.matches-reference", 42, { PersonAge: 42 }).value,
    true,
  );
});

test("rejects invariants whose primitive does not match the nominal type", () => {
  assert.throws(() => new SemanticAstBuilder()
    .addType(age)
    .addInvariant({
      ...isAdult,
      primitive: "string",
    })
    .build(), /uses primitive string/);
});

test("rejects references to undeclared nominal types", () => {
  assert.throws(() => new SemanticAstBuilder()
    .addType(age)
    .addInvariant({
      ...isAdult,
      expression: { kind: "reference", typeId: "MissingType" },
    })
    .build(), /Unknown referenced nominal type/);
});
