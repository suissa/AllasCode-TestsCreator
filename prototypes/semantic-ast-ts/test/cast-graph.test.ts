import assert from "node:assert/strict";
import test from "node:test";
import {
  SemanticAstBuilder,
  createDefaultCastingGraph,
  type NominalType,
} from "../src/index.js";

const age: NominalType = {
  kind: "nominal-type",
  id: "PersonAge",
  name: "PersonAge",
  primitive: "number",
  brand: "PersonAge",
};

function ast() {
  return new SemanticAstBuilder().addType(age).build();
}

test("enumerates reachable casting paths without changing the nominal type", () => {
  const graph = createDefaultCastingGraph();
  const paths = graph.pathsFrom("number", 2);
  assert.ok(paths.some((path) => path.length === 0));
  assert.ok(paths.some((path) => path.map((edge) => edge.id).join("/") === "number-to-string"));
  assert.ok(paths.some((path) => path.map((edge) => edge.id).join("/") === "number-to-string/string-to-boolean"));
  assert.equal(ast().types.get("PersonAge")?.primitive, "number");
});

test("keeps castability separate from semantic acceptance", async () => {
  const graph = createDefaultCastingGraph();
  const results = await graph.explore(ast(), "PersonAge", 21, {
    maxDepth: 1,
    accept: (candidate, context) => ({
      accepted: typeof candidate === "number" && candidate >= 18,
      reason: `process checked target ${context.targetPrimitive}`,
    }),
  });

  const identity = results.find((result) => result.cast.path.length === 0);
  const toString = results.find((result) => result.cast.targetPrimitive === "string");
  assert.equal(identity?.acceptance.accepted, true);
  assert.equal(toString?.cast.outcome.ok, true);
  assert.equal(toString?.acceptance.accepted, false);
  assert.equal(ast().types.get("PersonAge")?.primitive, "number");
});

test("records a failed conversion as a candidate outcome, not a graph mutation", async () => {
  const graph = createDefaultCastingGraph();
  const results = await graph.explore(ast(), "PersonAge", 7, {
    maxDepth: 1,
    accept: () => ({ accepted: true }),
  });
  assert.ok(results.length > 1);
  assert.ok(results.every((result) => result.cast.originalPrimitive === "number"));
});

test("does not traverse cycles or exceed max depth", () => {
  const graph = createDefaultCastingGraph();
  const paths = graph.pathsFrom("string", 3);
  assert.ok(paths.every((path) => path.length <= 3));
  assert.ok(paths.every((path) => new Set(path.map((edge) => edge.from).concat(
    path.length ? [path[path.length - 1]!.to] : [],
  )).size === path.length + (path.length ? 1 : 0)));
});
