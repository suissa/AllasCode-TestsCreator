const std = @import("std");
const model = @import("model.zig");
const synthetic = @import("synthetic.zig");

fn containsInteger(candidates: []const synthetic.Candidate, parameter: []const u8, expected: i64) bool {
    for (candidates) |candidate| {
        if (!std.mem.eql(u8, candidate.parameter, parameter)) continue;
        switch (candidate.value) {
            .integer => |value| if (value == expected) return true,
            else => {},
        }
    }
    return false;
}

fn containsString(candidates: []const synthetic.Candidate, parameter: []const u8, expected: []const u8) bool {
    for (candidates) |candidate| {
        if (!std.mem.eql(u8, candidate.parameter, parameter)) continue;
        switch (candidate.value) {
            .string => |value| if (std.mem.eql(u8, value, expected)) return true,
            else => {},
        }
    }
    return false;
}

fn countForParameter(candidates: []const synthetic.Candidate, parameter: []const u8) usize {
    var count: usize = 0;
    for (candidates) |candidate| {
        if (std.mem.eql(u8, candidate.parameter, parameter)) count += 1;
    }
    return count;
}

test "integer generation covers inclusive boundaries and semantic operands" {
    const allocator = std.testing.allocator;
    const parameters = [_]model.ParameterSpec{
        .{ .name = "age", .constraints = .{ .integer = .{ .min = 18, .max = 65 } } },
    };
    const predicates = [_]synthetic.Predicate{
        .{ .parameter = "age", .kind = .greater_equal, .integer_operand = 21 },
    };

    const candidates = try synthetic.generate(
        allocator,
        .{ .name = "isAdult", .parameters = &parameters },
        .{ .predicates = &predicates },
        .{ .seed = 123, .max_candidates_per_parameter = 16 },
    );
    defer synthetic.freeCandidates(allocator, candidates);

    try std.testing.expect(containsInteger(candidates, "age", 18));
    try std.testing.expect(containsInteger(candidates, "age", 65));
    try std.testing.expect(containsInteger(candidates, "age", 21));
}

test "generation respects the per-parameter candidate budget" {
    const allocator = std.testing.allocator;
    const parameters = [_]model.ParameterSpec{
        .{ .name = "count", .constraints = .{ .integer = .{ .min = -100, .max = 100 } } },
        .{ .name = "label", .constraints = .{ .string = .{ .min_len = 0, .max_len = 30 } } },
        .{ .name = "enabled", .constraints = .{ .boolean = {} } },
    };
    const candidates = try synthetic.generate(
        allocator,
        .{ .name = "sample", .parameters = &parameters },
        .{},
        .{ .seed = 7, .max_candidates_per_parameter = 4 },
    );
    defer synthetic.freeCandidates(allocator, candidates);

    try std.testing.expect(countForParameter(candidates, "count") <= 4);
    try std.testing.expect(countForParameter(candidates, "label") <= 4);
    try std.testing.expect(countForParameter(candidates, "enabled") <= 4);
}

test "string generation includes empty and transform operands when allowed" {
    const allocator = std.testing.allocator;
    const parameters = [_]model.ParameterSpec{
        .{ .name = "name", .constraints = .{ .string = .{ .min_len = 0, .max_len = 32 } } },
    };
    const transforms = [_]synthetic.Transform{
        .{ .parameter = "name", .kind = .trim, .string_operand = "  Alice  " },
    };
    const candidates = try synthetic.generate(
        allocator,
        .{ .name = "normalizeName", .parameters = &parameters },
        .{ .transforms = &transforms },
        .{ .seed = 9, .max_candidates_per_parameter = 24 },
    );
    defer synthetic.freeCandidates(allocator, candidates);

    try std.testing.expect(containsString(candidates, "name", ""));
    try std.testing.expect(containsString(candidates, "name", "  Alice  "));
}

test "same seed and specification produce the same ordered candidates" {
    const allocator = std.testing.allocator;
    const parameters = [_]model.ParameterSpec{
        .{ .name = "value", .constraints = .{ .integer = .{ .min = -50, .max = 50 } } },
    };
    const spec = model.FunctionSpec{ .name = "transform", .parameters = &parameters };
    const options = synthetic.GenerationOptions{ .seed = 42, .max_candidates_per_parameter = 20 };

    const first = try synthetic.generate(allocator, spec, .{}, options);
    defer synthetic.freeCandidates(allocator, first);
    const second = try synthetic.generate(allocator, spec, .{}, options);
    defer synthetic.freeCandidates(allocator, second);

    try std.testing.expectEqual(first.len, second.len);
    for (first, second) |left, right| {
        try std.testing.expectEqualStrings(left.parameter, right.parameter);
        try std.testing.expect(left.value == .integer and right.value == .integer);
        try std.testing.expectEqual(left.value.integer, right.value.integer);
        try std.testing.expectEqual(left.source, right.source);
    }
}

test "invalid numeric ranges are rejected" {
    const allocator = std.testing.allocator;
    const parameters = [_]model.ParameterSpec{
        .{ .name = "value", .constraints = .{ .integer = .{ .min = 10, .max = 1 } } },
    };

    try std.testing.expectError(
        synthetic.GenerationError.InvalidConstraintRange,
        synthetic.generate(
            allocator,
            .{ .name = "invalid", .parameters = &parameters },
            .{},
            .{ .seed = 1, .max_candidates_per_parameter = 8 },
        ),
    );
}

test "zero candidate budget is rejected" {
    const allocator = std.testing.allocator;
    const parameters = [_]model.ParameterSpec{
        .{ .name = "value", .constraints = .{ .integer = .{ .min = 0, .max = 1 } } },
    };

    try std.testing.expectError(
        synthetic.GenerationError.CandidateBudgetTooSmall,
        synthetic.generate(
            allocator,
            .{ .name = "emptyBudget", .parameters = &parameters },
            .{},
            .{ .max_candidates_per_parameter = 0 },
        ),
    );
}
