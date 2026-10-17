const std = @import("std");
const model = @import("model.zig");

/// Semantic hints extracted from a function body/AST by a language adapter.
/// TestsCreator itself remains language-neutral: adapters populate these hints.
pub const PredicateKind = enum { equal, not_equal, less_than, less_equal, greater_than, greater_equal, range, matches, is_empty, is_null, is_true };
pub const Predicate = struct {
    parameter: []const u8,
    kind: PredicateKind,
    integer_operand: ?i64 = null,
    string_operand: ?[]const u8 = null,
    second_integer_operand: ?i64 = null,
};
pub const TransformKind = enum { trim, lowercase, uppercase, normalize_whitespace, parse_integer, clamp, absolute, add, subtract, multiply, divide, substring, replace };
pub const Transform = struct {
    parameter: []const u8,
    kind: TransformKind,
    integer_operand: ?i64 = null,
    string_operand: ?[]const u8 = null,
};
pub const SemanticHints = struct {
    predicates: []const Predicate = &.{},
    transforms: []const Transform = &.{},
};

pub const CandidateSource = enum { minimum, maximum, adjacent_minimum, adjacent_maximum, midpoint, stratified, boolean_false, boolean_true, empty, whitespace, ascii_lower, ascii_upper, numeric_text, predicate_operand, transform_operand };
pub const Candidate = struct {
    parameter: []const u8,
    value: model.Value,
    source: CandidateSource,
};

pub const GenerationOptions = struct {
    seed: u64 = 1,
    max_candidates_per_parameter: usize = 64,
    max_string_bytes: usize = 256,
};

pub const GenerationError = error{InvalidConstraintRange, CandidateBudgetTooSmall, UnsupportedSemanticValue};

/// Deterministic boundary + stratified candidate generation. The algorithm
/// maximizes distinct semantic regions before spending budget on random values.
pub fn generate(
    allocator: std.mem.Allocator,
    spec: model.FunctionSpec,
    hints: SemanticHints,
    options: GenerationOptions,
) ![]Candidate {
    if (options.max_candidates_per_parameter == 0) return GenerationError.CandidateBudgetTooSmall;
    var out: std.ArrayList(Candidate) = .empty;
    errdefer {
        for (out.items) |candidate| freeValue(allocator, candidate.value);
        out.deinit(allocator);
    }

    for (spec.parameters) |param| {
        switch (param.constraints) {
            .integer => |c| try generateInteger(allocator, &out, param, c, hints, options),
            .string => |c| try generateString(allocator, &out, param, c, hints, options),
            .boolean => {
                try append(allocator, &out, param.name, .{ .boolean = false }, .boolean_false);
                if (options.max_candidates_per_parameter > 1)
                    try append(allocator, &out, param.name, .{ .boolean = true }, .boolean_true);
            },
        }
    }
    return try out.toOwnedSlice(allocator);
}

pub fn freeCandidates(allocator: std.mem.Allocator, candidates: []Candidate) void {
    for (candidates) |candidate| freeValue(allocator, candidate.value);
    allocator.free(candidates);
}

fn freeValue(allocator: std.mem.Allocator, value: model.Value) void {
    switch (value) { .string => |s| allocator.free(s), else => {} }
}

fn append(allocator: std.mem.Allocator, out: *std.ArrayList(Candidate), name: []const u8, value: model.Value, source: CandidateSource) !void {
    for (out.items) |existing| {
        if (!std.mem.eql(u8, existing.parameter, name) or existing.value != value) continue;
        switch (value) {
            .integer => |v| if (existing.value.integer == v) { freeValue(allocator, value); return; },
            .boolean => |v| if (existing.value.boolean == v) { freeValue(allocator, value); return; },
            .string => |v| if (std.mem.eql(u8, existing.value.string, v)) { freeValue(allocator, value); return; },
        }
    }
    try out.append(allocator, .{ .parameter = name, .value = value, .source = source });
}

fn withinBudget(out: *const std.ArrayList(Candidate), name: []const u8, budget: usize) bool {
    var count: usize = 0;
    for (out.items) |item| if (std.mem.eql(u8, item.parameter, name)) { count += 1; };
    return count < budget;
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
        // Equal-width strata cover the whole representable interval, not just its center.
        var i: usize = 1;
        while (i < 8 and withinBudget(out, param.name, budget)) : (i += 1) {
            const span: u128 = @intCast(@as(i128, hi) - @as(i128, lo));
            const offset = span / 8 * i + (span % 8 * i) / 8;
            const value: i64 = @intCast(@as(i128, lo) + @as(i128, @intCast(offset)));
            try addInt(allocator, out, param.name, value, .stratified, budget);
        }
    }
    for (hints.predicates) |p| {
        if (!std.mem.eql(u8, p.parameter, param.name)) continue;
        if (p.integer_operand) |v| if (v >= lo and v <= hi) try addInt(allocator, out, param.name, v, .predicate_operand, budget);
        if (p.second_integer_operand) |v| if (v >= lo and v <= hi) try addInt(allocator, out, param.name, v, .predicate_operand, budget);
    }
    for (hints.transforms) |t| {
        if (!std.mem.eql(u8, t.parameter, param.name)) continue;
        if (t.integer_operand) |v| if (v >= lo and v <= hi) try addInt(allocator, out, param.name, v, .transform_operand, budget);
    }
    // Seeded candidates are added only after boundaries, strata and semantic operands.
    var state = options.seed ^ 0x9e3779b97f4a7c15;
    while (withinBudget(out, param.name, budget)) {
        state = state *% 6364136223846793005 +% 1442695040888963407;
        const span: u128 = @intCast(@as(i128, hi) - @as(i128, lo) + 1);
        const offset = @as(u128, state) % span;
        try addInt(allocator, out, param.name, @intCast(@as(i128, lo) + @as(i128, @intCast(offset))), .stratified, budget);
        // Avoid an infinite loop when the domain contains fewer distinct values than the budget.
        if (hi -| lo < 2 and out.items.len > 0) break;
    }
}

fn addString(allocator: std.mem.Allocator, out: *std.ArrayList(Candidate), name: []const u8, value: []const u8, source: CandidateSource, budget: usize) !void {
    if (withinBudget(out, name, budget)) try append(allocator, out, name, .{ .string = try allocator.dupe(u8, value) }, source);
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
        while (i < 8 and withinBudget(out, param.name, budget)) : (i += 1) {
            try addStringLength(allocator, out, param.name, lo + ((hi - lo) / 8) * i, options.seed +% i, .stratified, budget);
        }
    }
    if (lo == 0) try addString(allocator, out, param.name, "", .empty, budget);
    try addString(allocator, out, param.name, " ", .whitespace, budget);
    try addString(allocator, out, param.name, "ABCxyz", .ascii_upper, budget);
    try addString(allocator, out, param.name, "0123456789", .numeric_text, budget);
    for (hints.predicates) |p| {
        if (std.mem.eql(u8, p.parameter, param.name)) if (p.string_operand) |v| {
            if (v.len >= lo and v.len <= hi) try addString(allocator, out, param.name, v, .predicate_operand, budget);
        };
    }
    for (hints.transforms) |t| {
        if (std.mem.eql(u8, t.parameter, param.name)) if (t.string_operand) |v| {
            if (v.len >= lo and v.len <= hi) try addString(allocator, out, param.name, v, .transform_operand, budget);
        };
    }
}

test "covers numeric boundaries and semantic predicate operands deterministically" {
    const allocator = std.testing.allocator;
    const params = [_]model.ParameterSpec{.{ .name = "age", .constraints = .{ .integer = .{ .min = 0, .max = 100 } } }};
    const predicates = [_]Predicate{.{ .parameter = "age", .kind = .equal, .integer_operand = 42 }};
    const a = try generate(allocator, .{ .name = "f", .parameters = &params }, .{ .predicates = &predicates }, .{ .seed = 4, .max_candidates_per_parameter = 16 });
    defer freeCandidates(allocator, a);
    var saw_min = false;
    var saw_max = false;
    var saw_operand = false;
    for (a) |item| switch (item.value) {
        .integer => |v| {
            if (v == 0) saw_min = true;
            if (v == 100) saw_max = true;
            if (v == 42) saw_operand = true;
        },
        else => {},
    };
    try std.testing.expect(saw_min and saw_max and saw_operand);
    const b = try generate(allocator, .{ .name = "f", .parameters = &params }, .{ .predicates = &predicates }, .{ .seed = 4, .max_candidates_per_parameter = 16 });
    defer freeCandidates(allocator, b);
    try std.testing.expectEqual(a.len, b.len);
}

test "covers both booleans and string transform shapes" {
    const allocator = std.testing.allocator;
    const params = [_]model.ParameterSpec{
        .{ .name = "enabled", .constraints = .{ .boolean = {} } },
        .{ .name = "name", .constraints = .{ .string = .{ .min_len = 0, .max_len = 20 } } },
    };
    const transforms = [_]Transform{.{ .parameter = "name", .kind = .trim, .string_operand = " value " }};
    const candidates = try generate(allocator, .{ .name = "f", .parameters = &params }, .{ .transforms = &transforms }, .{ .seed = 1, .max_candidates_per_parameter = 16 });
    defer freeCandidates(allocator, candidates);
    var false_seen = false;
    var true_seen = false;
    var trim_input_seen = false;
    for (candidates) |item| {
        if (std.mem.eql(u8, item.parameter, "enabled")) switch (item.value) {
            .boolean => |v| { if (v) true_seen = true else false_seen = true; },
            else => {},
        };
        if (std.mem.eql(u8, item.parameter, "name")) switch (item.value) {
            .string => |v| if (std.mem.eql(u8, v, " value ")) trim_input_seen = true,
            else => {},
        };
    }
    try std.testing.expect(false_seen and true_seen and trim_input_seen);
}
