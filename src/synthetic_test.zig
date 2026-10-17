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
    for (candidates) |candidate| if (std.mem.eql(u8, candidate.parameter, parameter)) count += 1;
    return count;
}

test "integer generation covers inclusive boundaries and semantic operands" {
    const allocator = std.testing.allocator;
    const parameters = [_]model.ParameterSpec{.{ .name = "age", .constraints = .{ .integer = .{ .min = 18, .max = 65 } } }};
    const predicates = [_]synthetic.Predicate{.{ .parameter = "age", .kind = .greater_equal, .integer_operand = 21 }};
    const candidates = try synthetic.generate(allocator, .{ .name = "isAdult", .parameters = &parameters }, .{ .predicates = &predicates }, .{ .seed = 123, .max_candidates_per_parameter = 16 });
    defer synthetic.freeCandidates(allocator, candidates);
    try std.testing.expect(containsInteger(candidates, "age", 18));
    try std.testing.expect(containsInteger(candidates, "age", 65));
    try std.testing.expect(containsInteger(candidates, "age", 21));
}

test "string candidates always respect declared length" {
    const allocator = std.testing.allocator;
    const parameters = [_]model.ParameterSpec{.{ .name = "name", .constraints = .{ .string = .{ .min_len = 2, .max_len = 4 } } }};
    const candidates = try synthetic.generate(allocator, .{ .name = "f", .parameters = &parameters }, .{}, .{ .seed = 1, .max_candidates_per_parameter = 32 });
    defer synthetic.freeCandidates(allocator, candidates);
    for (candidates) |candidate| switch (candidate.value) {
        .string => |value| try std.testing.expect(value.len >= 2 and value.len <= 4),
        else => {},
    };
}

test "predicate operands generate adjacent numeric boundary values" {
    const allocator = std.testing.allocator;
    const parameters = [_]model.ParameterSpec{.{ .name = "age", .constraints = .{ .integer = .{ .min = 0, .max = 100 } } }};
    const predicates = [_]synthetic.Predicate{.{ .parameter = "age", .kind = .greater_equal, .integer_operand = 21 }};
    const candidates = try synthetic.generate(allocator, .{ .name = "f", .parameters = &parameters }, .{ .predicates = &predicates }, .{ .seed = 1, .max_candidates_per_parameter = 32 });
    defer synthetic.freeCandidates(allocator, candidates);
    try std.testing.expect(containsInteger(candidates, "age", 20));
    try std.testing.expect(containsInteger(candidates, "age", 21));
    try std.testing.expect(containsInteger(candidates, "age", 22));
}

test "generation respects per-parameter budget and seed reproducibility" {
    const allocator = std.testing.allocator;
    const parameters = [_]model.ParameterSpec{.{ .name = "value", .constraints = .{ .integer = .{ .min = -100, .max = 100 } } }};
    const spec = model.FunctionSpec{ .name = "f", .parameters = &parameters };
    const options = synthetic.GenerationOptions{ .seed = 42, .max_candidates_per_parameter = 20 };
    const first = try synthetic.generate(allocator, spec, .{}, options);
    defer synthetic.freeCandidates(allocator, first);
    const second = try synthetic.generate(allocator, spec, .{}, options);
    defer synthetic.freeCandidates(allocator, second);
    try std.testing.expect(countForParameter(first, "value") <= 20);
    try std.testing.expectEqual(first.len, second.len);
    for (first, second) |left, right| {
        try std.testing.expectEqual(left.value.integer, right.value.integer);
        try std.testing.expectEqual(left.source, right.source);
    }
}

test "string transform operands are included only when valid" {
    const allocator = std.testing.allocator;
    const parameters = [_]model.ParameterSpec{.{ .name = "name", .constraints = .{ .string = .{ .min_len = 2, .max_len = 12 } } }};
    const transforms = [_]synthetic.Transform{.{ .parameter = "name", .kind = .trim, .string_operand = "  Alice  " }};
    const candidates = try synthetic.generate(allocator, .{ .name = "normalize", .parameters = &parameters }, .{ .transforms = &transforms }, .{ .seed = 9, .max_candidates_per_parameter = 24 });
    defer synthetic.freeCandidates(allocator, candidates);
    try std.testing.expect(containsString(candidates, "name", "  Alice  "));
    try std.testing.expect(!containsString(candidates, "name", ""));
}

test "invalid numeric range and zero budget are rejected" {
    const allocator = std.testing.allocator;
    const bad = [_]model.ParameterSpec{.{ .name = "value", .constraints = .{ .integer = .{ .min = 10, .max = 1 } } }};
    try std.testing.expectError(synthetic.GenerationError.InvalidConstraintRange, synthetic.generate(allocator, .{ .name = "invalid", .parameters = &bad }, .{}, .{ .max_candidates_per_parameter = 8 }));
    const valid = [_]model.ParameterSpec{.{ .name = "value", .constraints = .{ .integer = .{ .min = 0, .max = 1 } } }};
    try std.testing.expectError(synthetic.GenerationError.CandidateBudgetTooSmall, synthetic.generate(allocator, .{ .name = "empty", .parameters = &valid }, .{}, .{ .max_candidates_per_parameter = 0 }));
}
