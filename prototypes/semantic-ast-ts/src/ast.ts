/**
 * The AST correlates nominal types with their primitive representation and
 * with invariant expressions. It does not decide whether an input is valid.
 */

export const primitiveKinds = [
  "string",
  "number",
  "boolean",
  "bigint",
  "null",
  "undefined",
  "object",
  "array",
  "unknown",
] as const;

export type PrimitiveKind = (typeof primitiveKinds)[number];
export type TypeId = string;
export type InvariantId = string;

export interface NominalType {
  readonly kind: "nominal-type";
  readonly id: TypeId;
  readonly name: string;
  readonly primitive: PrimitiveKind;
  readonly brand?: string;
}

export interface LiteralExpression {
  readonly kind: "literal";
  readonly value: unknown;
  readonly primitive: PrimitiveKind;
}

export interface SelfExpression {
  readonly kind: "self";
}

export interface ReferenceExpression {
  readonly kind: "reference";
  readonly typeId: TypeId;
  readonly path?: readonly (string | number)[];
}

export type ArithmeticOperator = "add" | "subtract" | "multiply" | "divide" | "remainder";
export type ComparisonOperator = "eq" | "neq" | "gt" | "gte" | "lt" | "lte";
export type LogicalOperator = "and" | "or" | "not";

export interface ArithmeticExpression {
  readonly kind: "calculation";
  readonly operator: ArithmeticOperator;
  readonly left: Expression;
  readonly right: Expression;
}

export interface ComparisonExpression {
  readonly kind: "comparison";
  readonly operator: ComparisonOperator;
  readonly left: Expression;
  readonly right: Expression;
}

export interface LogicalExpression {
  readonly kind: "logical";
  readonly operator: LogicalOperator;
  readonly operands: readonly Expression[];
}

export interface StringLengthExpression {
  readonly kind: "string-length";
  readonly value: Expression;
}

export type Expression =
  | LiteralExpression
  | SelfExpression
  | ReferenceExpression
  | ArithmeticExpression
  | ComparisonExpression
  | LogicalExpression
  | StringLengthExpression;

export interface Invariant {
  readonly kind: "invariant";
  readonly id: InvariantId;
  /** Nominal type whose value is constrained by this invariant. */
  readonly ownerTypeId: TypeId;
  /** Primitive domain on which this invariant is defined. */
  readonly primitive: PrimitiveKind;
  /** The expression should evaluate to boolean. */
  readonly expression: Expression;
}

export interface SemanticAst {
  readonly types: ReadonlyMap<TypeId, NominalType>;
  readonly invariants: ReadonlyMap<InvariantId, Invariant>;
  readonly typesByPrimitive: ReadonlyMap<PrimitiveKind, readonly TypeId[]>;
  readonly invariantsByType: ReadonlyMap<TypeId, readonly InvariantId[]>;
  readonly invariantsByPrimitive: ReadonlyMap<PrimitiveKind, readonly InvariantId[]>;
}

export class SemanticAstBuilder {
  private readonly types = new Map<TypeId, NominalType>();
  private readonly invariants = new Map<InvariantId, Invariant>();

  addType(type: NominalType): this {
    if (!type.id.trim() || !type.name.trim()) {
      throw new Error("Nominal type id and name must not be empty");
    }
    if (this.types.has(type.id)) {
      throw new Error(`Duplicate nominal type id: ${type.id}`);
    }
    this.types.set(type.id, Object.freeze({ ...type }));
    return this;
  }

  addInvariant(invariant: Invariant): this {
    if (this.invariants.has(invariant.id)) {
      throw new Error(`Duplicate invariant id: ${invariant.id}`);
    }
    this.invariants.set(invariant.id, Object.freeze({ ...invariant }));
    return this;
  }

  build(): SemanticAst {
    for (const invariant of this.invariants.values()) {
      const owner = this.types.get(invariant.ownerTypeId);
      if (!owner) {
        throw new Error(`Unknown invariant owner type: ${invariant.ownerTypeId}`);
      }
      if (owner.primitive !== invariant.primitive) {
        throw new Error(
          `Invariant ${invariant.id} uses primitive ${invariant.primitive}, ` +
          `but ${owner.name} is backed by ${owner.primitive}`,
        );
      }
      this.assertReferencesExist(invariant.expression);
    }

    const typesByPrimitive = new Map<PrimitiveKind, TypeId[]>();
    const invariantsByType = new Map<TypeId, InvariantId[]>();
    const invariantsByPrimitive = new Map<PrimitiveKind, InvariantId[]>();

    for (const type of this.types.values()) {
      const ids = typesByPrimitive.get(type.primitive) ?? [];
      ids.push(type.id);
      typesByPrimitive.set(type.primitive, ids);
    }

    for (const invariant of this.invariants.values()) {
      const byType = invariantsByType.get(invariant.ownerTypeId) ?? [];
      byType.push(invariant.id);
      invariantsByType.set(invariant.ownerTypeId, byType);

      const byPrimitive = invariantsByPrimitive.get(invariant.primitive) ?? [];
      byPrimitive.push(invariant.id);
      invariantsByPrimitive.set(invariant.primitive, byPrimitive);
    }

    return Object.freeze({
      types: new Map(this.types),
      invariants: new Map(this.invariants),
      typesByPrimitive: freezeArrayMap(typesByPrimitive),
      invariantsByType: freezeArrayMap(invariantsByType),
      invariantsByPrimitive: freezeArrayMap(invariantsByPrimitive),
    });
  }

  private assertReferencesExist(expression: Expression): void {
    switch (expression.kind) {
      case "reference":
        if (!this.types.has(expression.typeId)) {
          throw new Error(`Unknown referenced nominal type: ${expression.typeId}`);
        }
        return;
      case "calculation":
      case "comparison":
        this.assertReferencesExist(expression.left);
        this.assertReferencesExist(expression.right);
        return;
      case "logical":
        if (expression.operands.length === 0) {
          throw new Error("Logical expressions require at least one operand");
        }
        if (expression.operator === "not" && expression.operands.length !== 1) {
          throw new Error("Logical 'not' requires exactly one operand");
        }
        if (expression.operator !== "not" && expression.operands.length < 2) {
          throw new Error(`Logical '${expression.operator}' requires at least two operands`);
        }
        expression.operands.forEach((operand) => this.assertReferencesExist(operand));
        return;
      case "string-length":
        this.assertReferencesExist(expression.value);
        return;
      case "literal":
      case "self":
        return;
    }
  }
}

function freezeArrayMap<K, V>(source: Map<K, V[]>): ReadonlyMap<K, readonly V[]> {
  return new Map([...source].map(([key, values]) => [key, Object.freeze([...values])]));
}
