const std = @import("std");
const dsl = @import("entity_dsl.zig");

/// The five canonical test families already emitted by semantic_compiler.zig.
pub const TestKind = enum { unit, load, stress, chaos, security };

pub const EvidenceContract = struct {
    /// Expectations are preserved verbatim; the runtime evaluates them.
    expectations: []const dsl.Expectation,
    result_authority: []const u8 = "runtime",
};

pub const LoweredCase = struct {
    kind: TestKind,
    entity: []const u8,
    inputs: []const dsl.Input,
    runs: []const dsl.Run,
    evidence: EvidenceContract,
};

pub const LoweredPlan = struct {
    cases: [5]LoweredCase,
};

/// Lowers syntax into the canonical test families without executing Actions.
/// Inputs, Action calls, and expectation expressions remain borrowed from the
/// parsed Scenario. Runtime evidence, not the compiler, decides pass/fail.
pub fn lower(scenario: *const dsl.Scenario) LoweredPlan {
    const kinds = [_]TestKind{ .unit, .load, .stress, .chaos, .security };
    var result: LoweredPlan = undefined;
    for (kinds, 0..) |kind, index| {
        result.cases[index] = .{
            .kind = kind,
            .entity = scenario.entity,
            .inputs = scenario.inputs,
            .runs = scenario.runs,
            .evidence = .{ .expectations = scenario.expectations },
        };
    }
    return result;
}

test "lowers Entity DSL to every canonical test kind" {
    const allocator = std.testing.allocator;
    var scenario = try dsl.parse(allocator,
        \\Entity: Person
        \\Input cpf = 04864713901
        \\Run validate(cpf)
        \\Expect isTruth
    );
    defer scenario.deinit(allocator);

    const plan = lower(&scenario);
    try std.testing.expectEqual(@as(usize, 5), plan.cases.len);
    try std.testing.expectEqual(TestKind.unit, plan.cases[0].kind);
    try std.testing.expectEqual(TestKind.load, plan.cases[1].kind);
    try std.testing.expectEqual(TestKind.stress, plan.cases[2].kind);
    try std.testing.expectEqual(TestKind.chaos, plan.cases[3].kind);
    try std.testing.expectEqual(TestKind.security, plan.cases[4].kind);
    for (plan.cases) |case| {
        try std.testing.expectEqualStrings("Person", case.entity);
        try std.testing.expectEqualStrings("validate", case.runs[0].action);
        try std.testing.expectEqualStrings("isTruth", case.evidence.expectations[0].predicate);
        try std.testing.expectEqualStrings("runtime", case.evidence.result_authority);
    }
}

test "lowering preserves Action arguments and expectation expressions" {
    const allocator = std.testing.allocator;
    var scenario = try dsl.parse(allocator,
        \\Entity: Order
        \\Input total = 100
        \\Run calculate(total)
        \\Expect equals(100)
    );
    defer scenario.deinit(allocator);

    const plan = lower(&scenario);
    try std.testing.expectEqualStrings("total", plan.cases[0].runs[0].arguments[0]);
    try std.testing.expectEqualStrings("equals(100)", plan.cases[0].evidence.expectations[0].predicate);
}
