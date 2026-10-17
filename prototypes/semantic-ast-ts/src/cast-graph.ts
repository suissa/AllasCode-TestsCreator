import type { PrimitiveKind, SemanticAst, TypeId } from "./ast.js";

export type CastRisk = "identity" | "lossless" | "lossy" | "conditional" | "unsafe";

export interface CastEdge {
  readonly id: string;
  readonly from: PrimitiveKind;
  readonly to: PrimitiveKind;
  readonly risk: CastRisk;
  readonly description: string;
  /** Produces a candidate. It does not declare that candidate semantically valid. */
  readonly convert: (value: unknown) => CastOutcome;
}

export type CastOutcome =
  | { readonly ok: true; readonly value: unknown }
  | { readonly ok: false; readonly reason: string };

export interface CastStep {
  readonly edgeId: string;
  readonly from: PrimitiveKind;
  readonly to: PrimitiveKind;
  readonly risk: CastRisk;
  readonly input: unknown;
  readonly output: unknown;
}

export interface CastPathResult {
  readonly nominalTypeId: TypeId;
  readonly originalPrimitive: PrimitiveKind;
  readonly targetPrimitive: PrimitiveKind;
  readonly path: readonly CastEdge[];
  readonly steps: readonly CastStep[];
  readonly outcome: CastOutcome;
}

export type AcceptanceResult =
  | { readonly accepted: true; readonly reason?: string }
  | { readonly accepted: false; readonly reason: string };

export interface ExploredCast {
  readonly cast: CastPathResult;
  readonly acceptance: AcceptanceResult;
}

/**
 * Enumerates possible primitive-to-primitive conversions without mutating the
 * declared nominal type. Semantic acceptance is deliberately delegated to the
 * caller's authoritative process/validator.
 */
export class TypeCastingGraph {
  private readonly adjacency = new Map<PrimitiveKind, CastEdge[]>();

  addEdge(edge: CastEdge): this {
    const edges = this.adjacency.get(edge.from) ?? [];
    if (edges.some((existing) => existing.id === edge.id)) {
      throw new Error(`Duplicate cast edge id '${edge.id}' from ${edge.from}`);
    }
    edges.push(Object.freeze({ ...edge }));
    this.adjacency.set(edge.from, edges);
    return this;
  }

  edgesFrom(kind: PrimitiveKind): readonly CastEdge[] {
    return this.adjacency.get(kind) ?? [];
  }

  /** Enumerate simple type paths up to maxDepth; no value is converted here. */
  pathsFrom(
    source: PrimitiveKind,
    maxDepth = 2,
    includeIdentity = true,
  ): CastEdge[][] {
    if (maxDepth < 0) throw new Error("maxDepth must be >= 0");
    const paths: CastEdge[][] = [];
    if (includeIdentity) paths.push([]);
    const walk = (
      current: PrimitiveKind,
      path: CastEdge[],
      visited: Set<PrimitiveKind>,
    ): void => {
      if (path.length >= maxDepth) return;
      for (const edge of this.edgesFrom(current)) {
        if (visited.has(edge.to)) continue;
        const nextPath = [...path, edge];
        paths.push(nextPath);
        const nextVisited = new Set(visited);
        nextVisited.add(edge.to);
        walk(edge.to, nextPath, nextVisited);
      }
    };
    walk(source, [], new Set([source]));
    return paths;
  }

  convertPath(
    nominalTypeId: TypeId,
    originalPrimitive: PrimitiveKind,
    value: unknown,
    path: readonly CastEdge[],
  ): CastPathResult {
    let current = value;
    let currentKind = originalPrimitive;
    const steps: CastStep[] = [];

    for (const edge of path) {
      if (edge.from !== currentKind) {
        return {
          nominalTypeId,
          originalPrimitive,
          targetPrimitive: currentKind,
          path,
          steps,
          outcome: { ok: false, reason: `Invalid path: expected edge from ${currentKind}, got ${edge.from}` },
        };
      }
      const result = edge.convert(current);
      if (!result.ok) {
        return {
          nominalTypeId,
          originalPrimitive,
          targetPrimitive: edge.to,
          path,
          steps,
          outcome: result,
        };
      }
      steps.push({
        edgeId: edge.id,
        from: edge.from,
        to: edge.to,
        risk: edge.risk,
        input: current,
        output: result.value,
      });
      current = result.value;
      currentKind = edge.to;
    }

    return {
      nominalTypeId,
      originalPrimitive,
      targetPrimitive: currentKind,
      path,
      steps,
      outcome: { ok: true, value: current },
    };
  }

  /**
   * Explores conversion paths and asks the supplied process whether each
   * resulting candidate is accepted. The original value/type is never changed.
   */
  async explore(
    ast: SemanticAst,
    nominalTypeId: TypeId,
    value: unknown,
    options: {
      maxDepth?: number;
      accept: (candidate: unknown, context: {
        nominalTypeId: TypeId;
        originalValue: unknown;
        originalPrimitive: PrimitiveKind;
        targetPrimitive: PrimitiveKind;
        path: readonly CastEdge[];
        cast: CastPathResult;
      }) => AcceptanceResult | Promise<AcceptanceResult>;
    },
  ): Promise<ExploredCast[]> {
    const nominal = ast.types.get(nominalTypeId);
    if (!nominal) throw new Error(`Unknown nominal type: ${nominalTypeId}`);

    const paths = this.pathsFrom(nominal.primitive, options.maxDepth ?? 2);
    const results: ExploredCast[] = [];
    for (const path of paths) {
      const cast = this.convertPath(nominal.id, nominal.primitive, value, path);
      if (!cast.outcome.ok) {
        results.push({ cast, acceptance: { accepted: false, reason: cast.outcome.reason } });
        continue;
      }
      const acceptance = await options.accept(cast.outcome.value, {
        nominalTypeId: nominal.id,
        originalValue: value,
        originalPrimitive: nominal.primitive,
        targetPrimitive: cast.targetPrimitive,
        path,
        cast,
      });
      results.push({ cast, acceptance });
    }
    return results;
  }
}

/** A deliberately broad default graph for fuzzing candidate generation. */
export function createDefaultCastingGraph(): TypeCastingGraph {
  const graph = new TypeCastingGraph();
  const edge = (
    id: string,
    from: PrimitiveKind,
    to: PrimitiveKind,
    risk: CastRisk,
    convert: CastEdge["convert"],
    description: string,
  ) => graph.addEdge({ id, from, to, risk, convert, description });

  edge("string-to-number", "string", "number", "conditional", (value) => {
    if (typeof value !== "string") return { ok: false, reason: "Expected string input" };
    return { ok: true, value: Number(value) };
  }, "JavaScript Number conversion; may yield NaN or infinity.");
  edge("number-to-string", "number", "string", "lossless", (value) =>
    typeof value === "number" ? { ok: true, value: String(value) } : { ok: false, reason: "Expected number input" },
  "String representation of a number.");
  edge("string-to-boolean", "string", "boolean", "lossy", (value) =>
    typeof value === "string" ? { ok: true, value: Boolean(value) } : { ok: false, reason: "Expected string input" },
  "JavaScript truthiness; even an empty string becomes false.");
  edge("boolean-to-string", "boolean", "string", "lossless", (value) =>
    typeof value === "boolean" ? { ok: true, value: String(value) } : { ok: false, reason: "Expected boolean input" },
  "Boolean textual representation.");
  edge("number-to-boolean", "number", "boolean", "lossy", (value) =>
    typeof value === "number" ? { ok: true, value: Boolean(value) } : { ok: false, reason: "Expected number input" },
  "Numeric truthiness.");
  edge("boolean-to-number", "boolean", "number", "lossless", (value) =>
    typeof value === "boolean" ? { ok: true, value: Number(value) } : { ok: false, reason: "Expected boolean input" },
  "Boolean maps to zero or one.");
  edge("string-to-array", "string", "array", "lossy", (value) =>
    typeof value === "string" ? { ok: true, value: [...value] } : { ok: false, reason: "Expected string input" },
  "String characters become array elements.");
  edge("array-to-string", "array", "string", "lossy", (value) =>
    Array.isArray(value) ? { ok: true, value: String(value) } : { ok: false, reason: "Expected array input" },
  "Array stringification.");
  edge("object-to-boolean", "object", "boolean", "lossy", (value) =>
    value !== null && typeof value === "object" ? { ok: true, value: true } : { ok: false, reason: "Expected object input" },
  "Non-null objects are truthy.");
  edge("null-to-undefined", "null", "undefined", "lossy", () => ({ ok: true, value: undefined }),
    "Candidate conversion from null to undefined.");
  edge("undefined-to-null", "undefined", "null", "lossy", () => ({ ok: true, value: null }),
    "Candidate conversion from undefined to null.");
  edge("unknown-to-string", "unknown", "string", "unsafe", (value) => {
    try { return { ok: true, value: String(value) }; }
    catch (error) { return { ok: false, reason: error instanceof Error ? error.message : "String conversion failed" }; }
  }, "Broad coercion from an unknown value.");

  // Identity is implicit: an empty path preserves the source value and type.
  return graph;
}
