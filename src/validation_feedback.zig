const std = @import("std");
const model = @import("model.zig");

/// Stable machine-readable violation codes. Validator adapters should map native
/// validation failures to these codes instead of asking the generator to parse prose.
pub const ViolationCode = enum {
    wrong_type,
    below_min,
    above_max,
    too_short,
    too_long,
    invariant_failed,
    normalization_failed,
};

pub const Diagnostic = struct {
    code: ViolationCode,
    parameter: []const u8,
    expected: []const u8,
    actual: []const u8,
    invariant: ?[]const u8 = null,
};

pub const RepairReason = enum { unchanged, clamped_to_min, clamped_to_max, padded_to_min, truncated_to_max };

/// Return the stable violation code for an integer candidate. The caller supplies
/// formatted expected/actual values to Diagnostic without leaking allocator ownership.
pub fn integerViolationCode(value: i64, constraints: model.IntConstraints) ?ViolationCode {
    if (constraints.min) |min| if (value < min) return .below_min;
    if (constraints.max) |max| if (value > max) return .above_max;
    return null;
}

/// Deterministic nearest-bound repair. Boundary and invalid cases must still be
/// retained separately; a repaired value is a new candidate, not a replacement
/// for the original failing example.
pub fn repairInteger(candidate: i64, constraints: model.IntConstraints) error{InvalidConstraintRange}!IntegerRepair {
    if (constraints.min) |min| {
        if (constraints.max) |max| if (min > max) return error.InvalidConstraintRange;
    }
    if (constraints.min) |min| {
        if (candidate < min) return .{ .value = min, .changed = true, .reason = .clamped_to_min };
    }
    if (constraints.max) |max| {
        if (candidate > max) return .{ .value = max, .changed = true, .reason = .clamped_to_max };
    }
    return .{ .value = candidate, .changed = false, .reason = .unchanged };
}

/// Length-directed repair preserves the candidate prefix when possible. This
/// only repairs length constraints; semantic/content constraints need their own
/// registered repair strategy and must not be guessed here.
pub fn repairString(allocator: std.mem.Allocator, candidate: []const u8, constraints: model.StringConstraints) ![]u8 {
    if (constraints.min_len) |min| {
        if (constraints.max_len) |max| if (min > max) return error.InvalidConstraintRange;
    }
    const target = if (constraints.min_len) |min| @max(candidate.len, min) else candidate.len;
    const bounded = if (constraints.max_len) |max| @min(target, max) else target;
    const repaired = try allocator.alloc(u8, bounded);
    const preserved = @min(candidate.len, bounded);
    @memcpy(repaired[0..preserved], candidate[0..preserved]);
    @memset(repaired[preserved..], 'x');
    return repaired;
}

test "diagnostics expose stable machine-readable fields and a repair instruction" {
    const allocator = std.testing.allocator;
    const text = try formatDiagnostic(allocator, .{
        .code = .below_min,
        .parameter = "age",
        .expected = "integer >= 18",
        .actual = "12",
    });
    defer allocator.free(text);
    try std.testing.expect(std.mem.indexOf(u8, text, "code=below_min") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "parameter=age") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "action=apply_targeted_repair_then_revalidate") != null);
}

test "integer validation identifies the exact violated bound" {
    try std.testing.expectEqual(ViolationCode.below_min, integerViolationCode(12, .{ .min = 18, .max = 120 }).?);
    try std.testing.expectEqual(ViolationCode.above_max, integerViolationCode(121, .{ .min = 18, .max = 120 }).?);
    try std.testing.expect(integerViolationCode(42, .{ .min = 18, .max = 120 }) == null);
}

test "integer repair clamps only to the violated nearest boundary" {
    const low = try repairInteger(12, .{ .min = 18, .max = 120 });
    try std.testing.expectEqual(@as(i64, 18), low.value);
    try std.testing.expectEqual(RepairReason.clamped_to_min, low.reason);
    const high = try repairInteger(140, .{ .min = 18, .max = 120 });
    try std.testing.expectEqual(@as(i64, 120), high.value);
    const valid = try repairInteger(42, .{ .min = 18, .max = 120 });
    try std.testing.expect(!valid.changed);
}

test "string repair pads or truncates to declared bounds deterministically" {
    const allocator = std.testing.allocator;
    const padded = try repairString(allocator, "a", .{ .min_len = 3, .max_len = 8 });
    defer allocator.free(padded);
    try std.testing.expectEqualStrings("axx", padded);
    const truncated = try repairString(allocator, "abcdef", .{ .min_len = 1, .max_len = 3 });
    defer allocator.free(truncated);
    try std.testing.expectEqualStrings("abc", truncated);
}

test "contradictory constraints return actionable errors" {
    try std.testing.expectError(error.InvalidConstraintRange, repairInteger(1, .{ .min = 10, .max = 2 }));
    const allocator = std.testing.allocator;
    try std.testing.expectError(error.InvalidConstraintRange, repairString(allocator, "x", .{ .min_len = 10, .max_len = 2 }));
}
