const std = @import("std");
const model = @import("model.zig");

pub const PredicateKind = enum { equal, not_equal, less_than, less_equal, greater_than, greater_equal, range, matches, is_empty, is_null, is_true };
pub const Predicate = struct {
    parameter: []const u8,
    kind: PredicateKind,
    integer_operand: ?i64 = null,
    string_operand: ?[]const u8 = null,
    second_integer_operand: ?i64 = null,
};
pub const TransformKind = enum { trim, lowercase, uppercase, normalize_whitespace, parse_integer, clamp, absolute, add, subtract, multiply, divide, substring, replace };
pub const Transform = struct { parameter: []const u8, kind: TransformKind, integer_operand: ?i64 = null, string_operand: ?[]const u8 = null };
pub const SemanticHints = struct { predicates: []const Predicate = &.{}, transforms: []const Transform = &.{} };

pub const CandidateSource = enum { minimum, maximum, adjacent_minimum, adjacent_maximum, midpoint, stratified, boolean_false, boolean_true, empty, whitespace, ascii_lower, ascii_upper, numeric_text, predicate_operand, transform_operand };
pub const Candidate = struct { parameter: []const u8, value: model.Value, source: CandidateSource };
pub const GenerationOptions = struct { seed: u64 = 1, max_candidates_per_parameter: usize = 64, max_string_bytes: usize = 256 };
pub const GenerationError = error{ InvalidConstraintRange, CandidateBudgetTooSmall, UnsupportedSemanticValue };

pub fn generate(allocator: std.mem.Allocator, spec: model.FunctionSpec, hints: SemanticHints, options: GenerationOptions) ![]Candidate {
    if (options.max_candidates_per_parameter == 0) return GenerationError.CandidateBudgetTooSmall;
    var out: std.ArrayList(Candidate) = .empty;
    errdefer {
        for (out.items) |candidate| freeValue(allocator, candidate.value);
        out.deinit(allocator);
    }
    for (spec.parameters) |param| switch (param.constraints) {
        .integer => |c| try generateInteger(allocator, &out, param, c, hints, options),
        .string => |c| try generateString(allocator, &out, param, c, hints, options),
        .boolean => {
            try append(allocator, &out, param.name, .{ .boolean = false }, .boolean_false);
            if (options.max_candidates_per_parameter > 1) try append(allocator, &out, param.name, .{ .boolean = true }, .boolean_true);
        },
    };
    return try out.toOwnedSlice(allocator);
}

pub fn freeCandidates(allocator: std.mem.Allocator, candidates: []Candidate) void {
    for (candidates) |candidate| freeValue(allocator, candidate.value);
    allocator.free(candidates);
}
fn freeValue(allocator: std.mem.Allocator, value: model.Value) void {
    switch (value) {
        .string => |s| allocator.free(s),
        else => {},
    }
}

fn append(allocator: std.mem.Allocator, out: *std.ArrayList(Candidate), name: []const u8, value: model.Value, source: CandidateSource) !void {
    for (out.items) |existing| {
        if (!std.mem.eql(u8, existing.parameter, name)) continue;
        const duplicate = switch (value) {
            .integer => |v| existing.value == .integer and existing.value.integer == v,
            .boolean => |v| existing.value == .boolean and existing.value.boolean == v,
            .string => |v| existing.value == .string and std.mem.eql(u8, existing.value.string, v),
        };
        if (duplicate) {
            freeValue(allocator, value);
            return;
        }
    }
    try out.append(allocator, .{ .parameter = name, .value = value, .source = source });
}
fn countFor(out: *const std.ArrayList(Candidate), name: []const u8) usize {
    var n: usize = 0;
    for (out.items) |x| if (std.mem.eql(u8, x.parameter, name)) n += 1;
    return n;
}
fn withinBudget(out: *const std.ArrayList(Candidate), name: []const u8, budget: usize) bool {
    return countFor(out, name) < budget;
}
fn addInt(allocator: std.mem.Allocator, out: *std.ArrayList(Candidate), name: []const u8, value: i64, source: CandidateSource, budget: usize) !void {
    if (withinBudget(out, name, budget)) try append(allocator, out, name, .{ .integer = value }, source);
}

fn generateInteger(allocator: std.mem.Allocator, out: *std.ArrayList(Candidate), param: model.ParameterSpec, c: model.IntConstraints, hints: SemanticHints, options: GenerationOptions) !void {
    const lo = c.min orelse std.math.minInt(i64);
    const hi = c.max orelse std.math.maxInt(i64);
    if (lo > hi) return GenerationError.InvalidConstraintRange;
    const budget = options.max_candidates_per_parameter;
    try addInt(allocator, out, param.name, lo, .minimum, budget);
    if (hi != lo) try addInt(allocator, out, param.name, hi, .maximum, budget);
    if (lo < hi) {
        try addInt(allocator, out, param.name, lo + 1, .adjacent_minimum, budget);
        try addInt(allocator, out, param.name, hi - 1, .adjacent_maximum, budget);
        const mid: i64 = @intCast(@as(i128, lo) + @divTrunc(@as(i128, hi) - @as(i128, lo), 2));
        try addInt(allocator, out, param.name, mid, .midpoint, budget);
    }
    for (hints.predicates) |p| {
        if (!std.mem.eql(u8, p.parameter, param.name)) continue;
        if (p.integer_operand) |v| {
            try addInt(allocator, out, param.name, v, .predicate_operand, budget);
            if (v > lo) try addInt(allocator, out, param.name, v - 1, .adjacent_minimum, budget);
            if (v < hi) try addInt(allocator, out, param.name, v + 1, .adjacent_maximum, budget);
        }
        if (p.second_integer_operand) |v| {
            try addInt(allocator, out, param.name, v, .predicate_operand, budget);
            if (v > lo) try addInt(allocator, out, param.name, v - 1, .adjacent_minimum, budget);
            if (v < hi) try addInt(allocator, out, param.name, v + 1, .adjacent_maximum, budget);
        }
    }
    for (hints.transforms) |t| if (std.mem.eql(u8, t.parameter, param.name)) if (t.integer_operand) |v| try addInt(allocator, out, param.name, v, .transform_operand, budget);
    var i: usize = 1;
    while (i <= 8 and withinBudget(out, param.name, budget)) : (i += 1) {
        const offset: i128 = @divTrunc((@as(i128, hi) - @as(i128, lo)) * @as(i128, i), 8);
        try addInt(allocator, out, param.name, @intCast(@as(i128, lo) + offset), .stratified, budget);
    }
    var state = options.seed ^ 0x9e3779b97f4a7c15;
    var attempts: usize = 0;
    while (withinBudget(out, param.name, budget) and attempts < budget * 4) : (attempts += 1) {
        state = state *% 6364136223846793005 +% 1442695040888963407;
        const span: u128 = @intCast(@as(i128, hi) - @as(i128, lo) + 1);
        try addInt(allocator, out, param.name, @intCast(@as(i128, lo) + @as(i128, @intCast(@as(u128, state) % span))), .stratified, budget);
    }
}

fn addString(allocator: std.mem.Allocator, out: *std.ArrayList(Candidate), name: []const u8, value: []const u8, source: CandidateSource, budget: usize, lo: usize, hi: usize) !void {
    if (value.len >= lo and value.len <= hi and withinBudget(out, name, budget)) try append(allocator, out, name, .{ .string = try allocator.dupe(u8, value) }, source);
}
fn addStringLength(allocator: std.mem.Allocator, out: *std.ArrayList(Candidate), name: []const u8, len: usize, seed: u64, source: CandidateSource, budget: usize) !void {
    if (!withinBudget(out, name, budget)) return;
    const value = try allocator.alloc(u8, len);
    @memset(value, 'a' + @as(u8, @intCast(seed % 26)));
    try append(allocator, out, name, .{ .string = value }, source);
}

fn generateString(allocator: std.mem.Allocator, out: *std.ArrayList(Candidate), param: model.ParameterSpec, c: model.StringConstraints, hints: SemanticHints, options: GenerationOptions) !void {
    const lo = c.min_len orelse 0;
    const hi = @min(c.max_len orelse 32, options.max_string_bytes);
    if (lo > hi) return GenerationError.InvalidConstraintRange;
    const budget = options.max_candidates_per_parameter;
    try addStringLength(allocator, out, param.name, lo, options.seed, .minimum, budget);
    if (hi != lo) {
        try addStringLength(allocator, out, param.name, hi, options.seed +% 1, .maximum, budget);
        if (lo < hi) try addStringLength(allocator, out, param.name, lo + 1, options.seed, .adjacent_minimum, budget);
        if (hi > lo) try addStringLength(allocator, out, param.name, hi - 1, options.seed, .adjacent_maximum, budget);
        try addStringLength(allocator, out, param.name, lo + (hi - lo) / 2, options.seed, .midpoint, budget);
        var i: usize = 1;
        while (i <= 8 and withinBudget(out, param.name, budget)) : (i += 1) try addStringLength(allocator, out, param.name, lo + ((hi - lo) * i) / 8, options.seed +% i, .stratified, budget);
    }
    try addString(allocator, out, param.name, "", .empty, budget, lo, hi);
    try addString(allocator, out, param.name, " ", .whitespace, budget, lo, hi);
    try addString(allocator, out, param.name, "ABCxyz", .ascii_upper, budget, lo, hi);
    try addString(allocator, out, param.name, "0123456789", .numeric_text, budget, lo, hi);
    for (hints.predicates) |p| if (std.mem.eql(u8, p.parameter, param.name)) if (p.string_operand) |v| try addString(allocator, out, param.name, v, .predicate_operand, budget, lo, hi);
    for (hints.transforms) |t| if (std.mem.eql(u8, t.parameter, param.name)) if (t.string_operand) |v| try addString(allocator, out, param.name, v, .transform_operand, budget, lo, hi);
}

test "covers numeric boundaries and semantic predicate operands deterministically" {
    const allocator = std.testing.allocator;
    const params = [_]model.ParameterSpec{.{ .name = "age", .constraints = .{ .integer = .{ .min = 0, .max = 100 } } }};
    const predicates = [_]Predicate{.{ .parameter = "age", .kind = .equal, .integer_operand = 42 }};
    const a = try generate(allocator, .{ .name = "f", .parameters = &params }, .{ .predicates = &predicates }, .{ .seed = 4, .max_candidates_per_parameter = 16 });
    defer freeCandidates(allocator, a);
    var min = false;
    var max = false;
    var operand = false;
    for (a) |x| switch (x.value) {
        .integer => |v| {
            if (v == 0) min = true;
            if (v == 100) max = true;
            if (v == 42) operand = true;
        },
        else => {},
    };
    try std.testing.expect(min and max and operand);
}

test "string candidates always respect declared length" {
    const allocator = std.testing.allocator;
    const params = [_]model.ParameterSpec{.{ .name = "name", .constraints = .{ .string = .{ .min_len = 2, .max_len = 4 } } }};
    const xs = try generate(allocator, .{ .name = "f", .parameters = &params }, .{}, .{ .seed = 1, .max_candidates_per_parameter = 32 });
    defer freeCandidates(allocator, xs);
    for (xs) |x| switch (x.value) {
        .string => |s| try std.testing.expect(s.len >= 2 and s.len <= 4),
        else => {},
    };
}

test "predicate operands generate adjacent numeric boundary values" {
    const allocator = std.testing.allocator;
    const params = [_]model.ParameterSpec{.{ .name = "age", .constraints = .{ .integer = .{ .min = 0, .max = 100 } } }};
    const ps = [_]Predicate{.{ .parameter = "age", .kind = .greater_equal, .integer_operand = 21 }};
    const xs = try generate(allocator, .{ .name = "f", .parameters = &params }, .{ .predicates = &ps }, .{ .seed = 1, .max_candidates_per_parameter = 32 });
    defer freeCandidates(allocator, xs);
    var a = false;
    var b = false;
    var c = false;
    for (xs) |x| switch (x.value) {
        .integer => |v| {
            if (v == 20) a = true;
            if (v == 21) b = true;
            if (v == 22) c = true;
        },
        else => {},
    };
    try std.testing.expect(a and b and c);
}

test "generation respects candidate budget and is deterministic" {
    const allocator = std.testing.allocator;
    const params = [_]model.ParameterSpec{.{ .name = "value", .constraints = .{ .integer = .{ .min = -100, .max = 100 } } }};
    const spec = model.FunctionSpec{ .name = "f", .parameters = &params };
    const opts = GenerationOptions{ .seed = 42, .max_candidates_per_parameter = 20 };
    const a = try generate(allocator, spec, .{}, opts);
    defer freeCandidates(allocator, a);
    const b = try generate(allocator, spec, .{}, opts);
    defer freeCandidates(allocator, b);
    try std.testing.expectEqual(a.len, b.len);
    for (a, b) |x, y| {
        try std.testing.expectEqual(x.value.integer, y.value.integer);
        try std.testing.expectEqual(x.source, y.source);
    }
}

test "invalid constraints and zero budget are rejected" {
    const allocator = std.testing.allocator;
    const bad = [_]model.ParameterSpec{.{ .name = "x", .constraints = .{ .integer = .{ .min = 10, .max = 1 } } }};
    try std.testing.expectError(GenerationError.InvalidConstraintRange, generate(allocator, .{ .name = "bad", .parameters = &bad }, .{}, .{}));
    const ok = [_]model.ParameterSpec{.{ .name = "x", .constraints = .{ .integer = .{ .min = 0, .max = 1 } } }};
    try std.testing.expectError(GenerationError.CandidateBudgetTooSmall, generate(allocator, .{ .name = "bad", .parameters = &ok }, .{}, .{ .max_candidates_per_parameter = 0 }));
}
