const std = @import("std");
const model = @import("model.zig");
const contract_generator = @import("generator.zig");

const max_fuzz_string_bytes = 256;
const fuzz_spec = model.FunctionSpec{
    .name = "CreateUser",
    .parameters = &.{
        .{ .name = "name", .constraints = .{ .string = .{ .min_len = 1, .max_len = 32 } } },
        .{ .name = "age", .constraints = .{ .integer = .{ .min = 18, .max = 120 } } },
        .{ .name = "active", .constraints = .{ .boolean = {} } },
    },
};

/// A contract-aware adapter over Zig 0.16's native Smith input stream.
/// It deliberately does not implement a second mutation/evolution engine.
pub fn generateArguments(allocator: std.mem.Allocator, smith: *std.testing.Smith, spec: model.FunctionSpec) ![]model.Argument {
    const args = try allocator.alloc(model.Argument, spec.parameters.len);
    var initialized: usize = 0;
    errdefer {
        for (args[0..initialized]) |arg| switch (arg.value) {
            .string => |value| allocator.free(value),
            else => {},
        };
        allocator.free(args);
    }

    for (spec.parameters, 0..) |param, i| {
        const value = try generateValue(allocator, smith, param.constraints);
        args[i] = .{ .name = param.name, .value = value };
        initialized += 1;
    }
    return args;
}

fn generateValue(allocator: std.mem.Allocator, smith: *std.testing.Smith, constraints: model.Constraints) !model.Value {
    return switch (constraints) {
        .boolean => .{ .boolean = smith.value(bool) },
        .integer => |c| blk: {
            const min = c.min orelse std.math.minInt(i64);
            const max = c.max orelse std.math.maxInt(i64);
            if (min > max) return error.InvalidConstraintRange;
            const mode = smith.valueRangeLessThan(u8, 0, 10);
            const value: i64 = if (mode < 3) min else if (mode < 6) max else if (mode == 6 and min < max) min + 1 else if (mode == 7 and min < max) max - 1 else blk2: {
                const raw = smith.value(i64);
                break :blk2 @max(min, @min(max, raw));
            };
            break :blk .{ .integer = value };
        },
        .string => |c| blk: {
            const min = c.min_len orelse 0;
            const max = @min(c.max_len orelse 32, max_fuzz_string_bytes);
            if (min > max) return error.ConstraintExceedsFuzzBudget;
            const mode = smith.valueRangeLessThan(u8, 0, 10);
            const len = if (mode < 3) min else if (mode < 6) max else if (mode == 6 and min < max) min + 1 else if (mode == 7 and min < max) max - 1 else min + smith.valueRangeLessThan(usize, 0, max - min + 1);
            const value = try allocator.alloc(u8, len);
            smith.bytes(value);
            break :blk .{ .string = value };
        },
    };
}

fn freeArguments(allocator: std.mem.Allocator, args: []model.Argument) void {
    for (args) |arg| switch (arg.value) {
        .string => |value| allocator.free(value),
        else => {},
    };
    allocator.free(args);
}

fn fuzzContract(_: void, smith: *std.testing.Smith) !void {
    const allocator = std.testing.allocator;
    const args = try generateArguments(allocator, smith, fuzz_spec);
    defer freeArguments(allocator, args);

    try std.testing.expectEqual(fuzz_spec.parameters.len, args.len);
    for (fuzz_spec.parameters, args) |param, arg| {
        try std.testing.expectEqualStrings(param.name, arg.name);
        switch (param.constraints) {
            .boolean => try std.testing.expect(arg.value == .boolean),
            .integer => |c| {
                try std.testing.expect(arg.value == .integer);
                if (c.min) |min| try std.testing.expect(arg.value.integer >= min);
                if (c.max) |max| try std.testing.expect(arg.value.integer <= max);
            },
            .string => |c| {
                try std.testing.expect(arg.value == .string);
                if (c.min_len) |min| try std.testing.expect(arg.value.string.len >= min);
                if (c.max_len) |max| try std.testing.expect(arg.value.string.len <= max);
            },
        }
    }

    var plan = try contract_generator.generate(allocator, fuzz_spec, smith.value(u64));
    defer plan.deinit(allocator);
    try std.testing.expect(plan.cases.len > 0);
}

test "native Smith generates contract-aware inputs and exercises canonical generator" {
    try std.testing.fuzz({}, fuzzContract, .{});
}
