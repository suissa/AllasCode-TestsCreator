import type {
  Expression,
  Invariant,
  NominalType,
  SemanticAst,
  TypeId,
} from "./ast.js";

export type EvaluationResult =
  | { readonly ok: true; readonly value: unknown }
  | { readonly ok: false; readonly error: string };

export interface EvaluationContext {
  /** Candidate being tested for the invariant's owner type. */
  readonly self: unknown;
  /** Other candidate values, keyed by nominal type id. */
  readonly values?: Readonly<Record<TypeId, unknown>>;
}

export interface InvariantResult {
  readonly invariantId: string;
  readonly ownerTypeId: TypeId;
  readonly ok: boolean;
  readonly value?: boolean;
  readonly evaluationError?: string;
}

export function evaluateExpression(
  expression: Expression,
  context: EvaluationContext,
): EvaluationResult {
  try {
    switch (expression.kind) {
      case "literal":
        return { ok: true, value: expression.value };
      case "self":
        return { ok: true, value: context.self };
      case "reference": {
        const root = context.values?.[expression.typeId];
        if (root === undefined && !Object.hasOwn(context.values ?? {}, expression.typeId)) {
          return { ok: false, error: `Missing value for type ${expression.typeId}` };
        }
        let value: unknown = root;
        for (const segment of expression.path ?? []) {
          if ((typeof value !== "object" && typeof value !== "function") || value === null) {
            return { ok: false, error: `Cannot read path segment ${String(segment)} from non-object` };
          }
          value = (value as Record<string | number, unknown>)[segment];
        }
        return { ok: true, value };
      }
      case "calculation": {
        const left = evaluateExpression(expression.left, context);
        if (!left.ok) return left;
        const right = evaluateExpression(expression.right, context);
        if (!right.ok) return right;
        if (typeof left.value !== "number" || typeof right.value !== "number") {
          return { ok: false, error: `Calculation '${expression.operator}' requires numeric operands` };
        }
        switch (expression.operator) {
          case "add": return { ok: true, value: left.value + right.value };
          case "subtract": return { ok: true, value: left.value - right.value };
          case "multiply": return { ok: true, value: left.value * right.value };
          case "divide":
            return right.value === 0
              ? { ok: false, error: "Division by zero" }
              : { ok: true, value: left.value / right.value };
          case "remainder":
            return right.value === 0
              ? { ok: false, error: "Remainder by zero" }
              : { ok: true, value: left.value % right.value };
        }
      }
      case "comparison": {
        const left = evaluateExpression(expression.left, context);
        if (!left.ok) return left;
        const right = evaluateExpression(expression.right, context);
        if (!right.ok) return right;
        switch (expression.operator) {
          case "eq": return { ok: true, value: left.value === right.value };
          case "neq": return { ok: true, value: left.value !== right.value };
          case "gt":
          case "gte":
          case "lt":
          case "lte": {
            if (
              (typeof left.value !== "number" || typeof right.value !== "number") &&
              (typeof left.value !== "string" || typeof right.value !== "string")
            ) {
              return { ok: false, error: `Comparison '${expression.operator}' requires two numbers or two strings` };
            }
            if (expression.operator === "gt") return { ok: true, value: left.value > (right.value as never) };
            if (expression.operator === "gte") return { ok: true, value: left.value >= (right.value as never) };
            if (expression.operator === "lt") return { ok: true, value: left.value < (right.value as never) };
            return { ok: true, value: left.value <= (right.value as never) };
          }
        }
      }
      case "logical": {
        const values: boolean[] = [];
        for (const operand of expression.operands) {
          const result = evaluateExpression(operand, context);
          if (!result.ok) return result;
          if (typeof result.value !== "boolean") {
            return { ok: false, error: `Logical '${expression.operator}' requires boolean operands` };
          }
          values.push(result.value);
        }
        if (expression.operator === "not") return { ok: true, value: !values[0] };
        if (expression.operator === "and") return { ok: true, value: values.every(Boolean) };
        return { ok: true, value: values.some(Boolean) };
      }
      case "string-length": {
        const result = evaluateExpression(expression.value, context);
        if (!result.ok) return result;
        if (typeof result.value !== "string") {
          return { ok: false, error: "string-length requires a string operand" };
        }
        return { ok: true, value: result.value.length };
      }
    }
  } catch (error) {
    return {
      ok: false,
      error: error instanceof Error ? error.message : "Unknown expression evaluation error",
    };
  }
}

export function evaluateInvariant(
  ast: SemanticAst,
  invariantId: string,
  candidate: unknown,
  values: Readonly<Record<TypeId, unknown>> = {},
): InvariantResult {
  const invariant = ast.invariants.get(invariantId);
  if (!invariant) {
    return {
      invariantId,
      ownerTypeId: "",
      ok: false,
      evaluationError: `Unknown invariant: ${invariantId}`,
    };
  }

  const evaluated = evaluateExpression(invariant.expression, {
    self: candidate,
    values,
  });

  if (!evaluated.ok) {
    return {
      invariantId,
      ownerTypeId: invariant.ownerTypeId,
      ok: false,
      evaluationError: evaluated.error,
    };
  }

  if (typeof evaluated.value !== "boolean") {
    return {
      invariantId,
      ownerTypeId: invariant.ownerTypeId,
      ok: false,
      evaluationError: "Invariant expression did not evaluate to boolean",
    };
  }

  return {
    invariantId,
    ownerTypeId: invariant.ownerTypeId,
    ok: true,
    value: evaluated.value,
  };
}

/** Returns the primitive representation linked to a nominal type. */
export function primitiveForType(ast: SemanticAst, typeId: TypeId): NominalType["primitive"] | undefined {
  return ast.types.get(typeId)?.primitive;
}

/** Exposes invariant IDs correlated to a nominal type without evaluating them. */
export function invariantsForType(ast: SemanticAst, typeId: TypeId): readonly Invariant[] {
  const ids = ast.invariantsByType.get(typeId) ?? [];
  return ids.flatMap((id) => {
    const invariant = ast.invariants.get(id);
    return invariant ? [invariant] : [];
  });
}
