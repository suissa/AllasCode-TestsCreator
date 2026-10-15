const std = @import("std");
const model = @import("model.zig");

pub const Options = struct { population: usize = 12, generations: usize = 8, mutations_per_candidate: usize = 4 };
pub const Candidate = struct { arguments: []model.Argument, score: u64 };
pub const FuzzPlan = struct { cases: []model.TestCase, generations: usize, evaluated: usize, unique_inputs: usize,
    pub fn deinit(self: *FuzzPlan, allocator: std.mem.Allocator) void { for (self.cases) |case| { allocator.free(case.name); for (case.arguments) |arg| switch (arg.value) { .string => |s| allocator.free(s), else => {} }; allocator.free(case.arguments); } allocator.free(self.cases); }
};

/// Adaptive evolutionary fuzzing. Candidates are selected by boundary proximity and
/// mutated around the highest-value frontier instead of uniformly sampling the space.
pub fn generate(allocator: std.mem.Allocator, spec: model.FunctionSpec, seed: u64, options: Options) !FuzzPlan {
    if (options.population == 0 or options.generations == 0 or options.mutations_per_candidate == 0) return error.InvalidOptions;
    var population = std.ArrayList(Candidate).empty; defer deinitPopulation(allocator, &population);
    var cases = std.ArrayList(model.TestCase).empty; errdefer deinitCases(allocator, &cases);
    var seen = std.StringHashMap(void).init(allocator); defer seen.deinit();
    var rng = std.Random.DefaultPrng.init(seed); var evaluated: usize = 0;
    for (0..options.population) |_| { const args = try randomArguments(allocator, spec, rng.random()); try population.append(allocator, .{ .arguments = args, .score = frontierScore(spec, args) }); }
    for (0..options.generations) |generation| {
        std.sort.heap(Candidate, population.items, {}, lessCandidate);
        const elite = @max(@as(usize, 1), population.items.len / 3);
        var next = std.ArrayList(Candidate).empty; errdefer deinitPopulation(allocator, &next);
        for (population.items[0..elite]) |parent| try next.append(allocator, .{ .arguments = try cloneArguments(allocator, parent.arguments), .score = parent.score });
        for (population.items[0..elite]) |parent| {
            for (0..options.mutations_per_candidate) |mutation_index| {
            var child = try cloneArguments(allocator, parent.arguments);
            mutateArguments(allocator, spec, child, rng.random(), generation + mutation_index);
            const score = frontierScore(spec, child); evaluated += 1;
            const key = try fingerprint(allocator, child); defer allocator.free(key);
            if (!seen.contains(key)) { try seen.put(key, {}); const name = try std.fmt.allocPrint(allocator, "fuzz.g{d}.m{d}.score{d}", .{ generation, mutation_index, score }); try cases.append(allocator, .{ .name = name, .kind = .valid, .arguments = try cloneArguments(allocator, child) }); }
            try next.append(allocator, .{ .arguments = child, .score = score });
            }
        }
        deinitPopulation(allocator, &population); population = next;
    }
    return .{ .cases = try cases.toOwnedSlice(allocator), .generations = options.generations, .evaluated = evaluated, .unique_inputs = seen.count() };
}
fn lessCandidate(_: void, a: Candidate, b: Candidate) bool { return a.score > b.score; }
fn frontierScore(spec: model.FunctionSpec, args: []const model.Argument) u64 { var score: u64 = 0; for (spec.parameters, 0..) |param, i| switch (param.constraints) {
    .string => |c| { const len = args[i].value.string.len; if (c.min_len) |min| score += if (len <= min + 1) 100 else 1; if (c.max_len) |max| score += if (len + 1 >= max) 100 else 1; },
    .integer => |c| { const v = args[i].value.integer; if (c.min) |min| score += if (distance(v, min) <= 1) 100 else 1; if (c.max) |max| score += if (distance(v, max) <= 1) 100 else 1; },
    .boolean => score += 1,
}; return score; }
fn distance(a: i64, b: i64) u64 { const d: i128 = @as(i128, a) - @as(i128, b); return @intCast(if (d < 0) -d else d); }
fn randomArguments(allocator: std.mem.Allocator, spec: model.FunctionSpec, random: std.Random) ![]model.Argument { const args = try allocator.alloc(model.Argument, spec.parameters.len); errdefer allocator.free(args); for (spec.parameters, 0..) |param, i| args[i] = .{ .name = param.name, .value = try randomValue(allocator, param.constraints, random) }; return args; }
fn randomValue(allocator: std.mem.Allocator, constraints: model.Constraints, random: std.Random) !model.Value { return switch (constraints) {
    .string => |c| blk: { const min = c.min_len orelse 0; const max = c.max_len orelse @max(min, 32); if (min > max) return error.InvalidConstraintRange; const span = @min(max - min + 1, @as(usize, 33)); const len = min + random.uintLessThan(usize, span); const s = try allocator.alloc(u8, len); for (s) |*ch| ch.* = @as(u8, 'a') + random.uintLessThan(u8, 26); break :blk .{ .string = s }; },
    .integer => |c| blk: { const min = c.min orelse -1000; const max = c.max orelse 1000; if (min > max) return error.InvalidConstraintRange; const span: u128 = @as(u128, @intCast(@as(i128, max) - @as(i128, min) + 1)); const offset: i128 = @intCast(random.int(u64) % @as(u64, @intCast(@min(span, std.math.maxInt(u64))))); break :blk .{ .integer = @intCast(@as(i128, min) + offset) }; },
    .boolean => .{ .boolean = random.boolean() },
}; }
fn mutateArguments(allocator: std.mem.Allocator, spec: model.FunctionSpec, args: []model.Argument, random: std.Random, salt: usize) void { if (args.len == 0) return; const index = (random.uintLessThan(usize, args.len) + salt) % args.len; switch (spec.parameters[index].constraints) {
    .string => |c| { allocator.free(args[index].value.string); const min = c.min_len orelse 0; const max = c.max_len orelse @max(min, 32); const mode = random.uintLessThan(u8, 4); const len = switch (mode) { 0 => min, 1 => if (max > min) max - 1 else max, 2 => max, else => if (max > min) min + random.uintLessThan(usize, @min(max - min + 1, 33)) else min }; const s = allocator.alloc(u8, len) catch return; @memset(s, @as(u8, 'a') + random.uintLessThan(u8, 26)); args[index].value = .{ .string = s }; },
    .integer => |c| { const min = c.min orelse -1000; const max = c.max orelse 1000; const mode = random.uintLessThan(u8, 4); const v = switch (mode) { 0 => min, 1 => max, 2 => if (min < max) min + 1 else min, else => if (min < max) max - 1 else max }; args[index].value = .{ .integer = v }; },
    .boolean => args[index].value = .{ .boolean = !args[index].value.boolean },
} }
fn cloneArguments(allocator: std.mem.Allocator, args: []const model.Argument) ![]model.Argument { const copy = try allocator.alloc(model.Argument, args.len); errdefer allocator.free(copy); for (args, 0..) |arg, i| copy[i] = .{ .name = arg.name, .value = switch (arg.value) { .string => |s| .{ .string = try allocator.dupe(u8, s) }, .integer => |v| .{ .integer = v }, .boolean => |v| .{ .boolean = v } } }; return copy; }
fn fingerprint(allocator: std.mem.Allocator, args: []const model.Argument) ![]u8 { var out = std.ArrayList(u8).empty; for (args) |arg| { try out.appendSlice(allocator, arg.name); try out.append(allocator, ':'); switch (arg.value) { .string => |s| try out.appendSlice(allocator, s), .integer => |v| try std.fmt.format(out.writer(allocator), "{d}", .{v}), .boolean => |v| try std.fmt.format(out.writer(allocator), "{any}", .{v}) }; try out.append(allocator, ';'); } return out.toOwnedSlice(allocator); }
fn deinitPopulation(allocator: std.mem.Allocator, population: *std.ArrayList(Candidate)) void { for (population.items) |candidate| { for (candidate.arguments) |arg| switch (arg.value) { .string => |s| allocator.free(s), else => {} }; allocator.free(candidate.arguments); } population.deinit(allocator); }
fn deinitCases(allocator: std.mem.Allocator, cases: *std.ArrayList(model.TestCase)) void { for (cases.items) |case| { allocator.free(case.name); for (case.arguments) |arg| switch (arg.value) { .string => |s| allocator.free(s), else => {} }; allocator.free(case.arguments); } cases.deinit(allocator); }

test "evolution concentrates inputs near constraint frontiers" { const allocator = std.testing.allocator; const params = [_]model.ParameterSpec{ .{ .name = "age", .constraints = .{ .integer = .{ .min = 18, .max = 120 } } }, .{ .name = "name", .constraints = .{ .string = .{ .min_len = 2, .max_len = 8 } } } }; var plan = try generate(allocator, .{ .name = "CreateUser", .parameters = &params }, 42, .{ .population = 8, .generations = 5, .mutations_per_candidate = 3 }); defer plan.deinit(allocator); try std.testing.expect(plan.cases.len > 0); try std.testing.expect(plan.evaluated > 0); try std.testing.expect(plan.unique_inputs > 0); }
test "same seed is deterministic" { const allocator = std.testing.allocator; const params = [_]model.ParameterSpec{.{ .name = "age", .constraints = .{ .integer = .{ .min = 1, .max = 5 } } }}; var a = try generate(allocator, .{ .name = "F", .parameters = &params }, 7, .{ .population = 4, .generations = 2, .mutations_per_candidate = 2 }); defer a.deinit(allocator); var b = try generate(allocator, .{ .name = "F", .parameters = &params }, 7, .{ .population = 4, .generations = 2, .mutations_per_candidate = 2 }); defer b.deinit(allocator); try std.testing.expectEqual(a.cases.len, b.cases.len); }
