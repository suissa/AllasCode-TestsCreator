const std = @import("std");
const model = @import("model.zig");

pub const GenerationError = error{InvalidConstraintRange};

pub fn generate(allocator: std.mem.Allocator, spec: model.FunctionSpec, seed: u64) !model.TestPlan {
    var cases = std.ArrayList(model.TestCase).empty;
    errdefer {
        for (cases.items) |case| {
            allocator.free(case.name);
            freeArguments(allocator, case.arguments);
        }
        cases.deinit(allocator);
    }

    try cases.append(allocator, .{
        .name = try allocator.dupe(u8, "valid.default"),
        .kind = .valid,
        .arguments = try defaultArguments(allocator, spec, seed),
    });

    for (spec.parameters, 0..) |param, index| {
        switch (param.constraints) {
            .string => |c| {
                if (c.min_len != null and c.max_len != null and c.min_len.? > c.max_len.?)
                    return GenerationError.InvalidConstraintRange;
                if (c.min_len) |min_len| {
                    try appendStringCase(allocator, &cases, spec, seed, index, param.name, "boundary", "min", min_len, .boundary, null);
                    if (min_len > 0)
                        try appendStringCase(allocator, &cases, spec, seed, index, param.name, "invalid", "too_short", min_len - 1, .invalid, param.name);
                }
                if (c.max_len) |max_len| {
                    try appendStringCase(allocator, &cases, spec, seed, index, param.name, "boundary", "max", max_len, .boundary, null);
                    if (max_len < std.math.maxInt(usize))
                        try appendStringCase(allocator, &cases, spec, seed, index, param.name, "invalid", "too_long", max_len + 1, .invalid, param.name);
                }
            },
            .integer => |c| {
                if (c.min != null and c.max != null and c.min.? > c.max.?)
                    return GenerationError.InvalidConstraintRange;
                if (c.min) |min| {
                    try appendIntCase(allocator, &cases, spec, seed, index, param.name, "boundary", "min", min, .boundary, null);
                    if (min > std.math.minInt(i64))
                        try appendIntCase(allocator, &cases, spec, seed, index, param.name, "invalid", "below_min", min - 1, .invalid, param.name);
                }
                if (c.max) |max| {
                    try appendIntCase(allocator, &cases, spec, seed, index, param.name, "boundary", "max", max, .boundary, null);
                    if (max < std.math.maxInt(i64))
                        try appendIntCase(allocator, &cases, spec, seed, index, param.name, "invalid", "above_max", max + 1, .invalid, param.name);
                }
            },
            .boolean => {
                var args = try defaultArguments(allocator, spec, seed);
                args[index].value = .{ .boolean = false };
                try cases.append(allocator, .{
                    .name = try std.fmt.allocPrint(allocator, "boundary.{s}.false", .{param.name}),
                    .kind = .boundary,
                    .arguments = args,
                });
            },
        }
    }

    return .{ .function_name = spec.name, .seed = seed, .cases = try cases.toOwnedSlice(allocator) };
}

fn defaultArguments(allocator: std.mem.Allocator, spec: model.FunctionSpec, seed: u64) ![]model.Argument {
    const args = try allocator.alloc(model.Argument, spec.parameters.len);
    errdefer allocator.free(args);
    var initialized: usize = 0;
    errdefer for (args[0..initialized]) |arg| switch (arg.value) {
        .string => |s| allocator.free(s),
        else => {},
    };

    for (spec.parameters, 0..) |param, i| {
        args[i] = .{ .name = param.name, .value = try defaultValue(allocator, param.constraints, seed +% i) };
        initialized += 1;
    }
    return args;
}

fn defaultValue(allocator: std.mem.Allocator, constraints: model.Constraints, seed: u64) !model.Value {
    return switch (constraints) {
        .string => |c| blk: {
            const min_len = c.min_len orelse 1;
            const max_len = c.max_len orelse @max(min_len, 8);
            if (min_len > max_len) return GenerationError.InvalidConstraintRange;
            const span = max_len - min_len + 1;
            const target = min_len + @as(usize, @intCast(seed % span));
            break :blk .{ .string = try repeatAscii(allocator, target, seed) };
        },
        .integer => |c| blk: {
            const min = c.min orelse 0;
            const max = c.max orelse @max(min, 100);
            if (min > max) return GenerationError.InvalidConstraintRange;
            const value = if (min == max) min else min + @as(i64, @intCast(seed % @as(u64, @intCast(max - min + 1))));
            break :blk .{ .integer = value };
        },
        .boolean => .{ .boolean = (seed & 1) == 0 },
    };
}

fn appendStringCase(allocator: std.mem.Allocator, cases: *std.ArrayList(model.TestCase), spec: model.FunctionSpec, seed: u64, index: usize, param_name: []const u8, prefix: []const u8, suffix: []const u8, len: usize, kind: model.CaseKind, invalid_parameter: ?[]const u8) !void {
    var args = try defaultArguments(allocator, spec, seed);
    errdefer freeArguments(allocator, args);
    switch (args[index].value) { .string => |old| allocator.free(old), else => {} }
    args[index].value = .{ .string = try repeatAscii(allocator, len, seed +% index) };
    const name = try std.fmt.allocPrint(allocator, "{s}.{s}.{s}", .{prefix, param_name, suffix});
    errdefer allocator.free(name);
    try cases.append(allocator, .{ .name = name, .kind = kind, .invalid_parameter = invalid_parameter, .arguments = args });
}

fn appendIntCase(allocator: std.mem.Allocator, cases: *std.ArrayList(model.TestCase), spec: model.FunctionSpec, seed: u64, index: usize, param_name: []const u8, prefix: []const u8, suffix: []const u8, value: i64, kind: model.CaseKind, invalid_parameter: ?[]const u8) !void {
    const args = try defaultArguments(allocator, spec, seed);
    errdefer freeArguments(allocator, args);
    args[index].value = .{ .integer = value };
    const name = try std.fmt.allocPrint(allocator, "{s}.{s}.{s}", .{prefix, param_name, suffix});
    errdefer allocator.free(name);
    try cases.append(allocator, .{ .name = name, .kind = kind, .invalid_parameter = invalid_parameter, .arguments = args });
}

fn repeatAscii(allocator: std.mem.Allocator, len: usize, seed: u64) ![]u8 {
    const out = try allocator.alloc(u8, len);
    const c: u8 = 'a' + @as(u8, @intCast(seed % 26));
    @memset(out, c);
    return out;
}

fn freeArguments(allocator: std.mem.Allocator, args: []model.Argument) void {
    for (args) |arg| switch (arg.value) {
        .string => |s| allocator.free(s),
        else => {},
    };
    allocator.free(args);
}

test "one valid plus isolated boundary and invalid cases" {
    const allocator = std.testing.allocator;
    const params = [_]model.ParameterSpec{
        .{ .name = "name", .constraints = .{ .string = .{ .min_len = 1, .max_len = 4 } } },
        .{ .name = "age", .constraints = .{ .integer = .{ .min = 18, .max = 120 } } },
    };
    var plan = try generate(allocator, .{ .name = "CreateUser", .parameters = &params }, 42);
    defer plan.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 9), plan.cases.len);
    try std.testing.expectEqualStrings("valid.default", plan.cases[0].name);
    var invalid: usize = 0;
    for (plan.cases) |case| if (case.kind == .invalid) {
        invalid += 1;
        try std.testing.expect(case.invalid_parameter != null);
    };
    try std.testing.expectEqual(@as(usize, 4), invalid);
    try std.testing.expect(plan.policy.test);
    try std.testing.expect(plan.policy.ephemeral);
    try std.testing.expect(!plan.policy.persist_payload);
    try std.testing.expect(!plan.policy.persist_events);
}

test "same seed is reproducible" {
    const allocator = std.testing.allocator;
    const params = [_]model.ParameterSpec{
        .{ .name = "age", .constraints = .{ .integer = .{ .min = 18, .max = 120 } } },
    };
    var a = try generate(allocator, .{ .name = "F", .parameters = &params }, 7);
    defer a.deinit(allocator);
    var b = try generate(allocator, .{ .name = "F", .parameters = &params }, 7);
    defer b.deinit(allocator);
    try std.testing.expectEqual(a.cases[0].arguments[0].value.integer, b.cases[0].arguments[0].value.integer);
}
