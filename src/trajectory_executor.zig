const std = @import("std");
const trajectory = @import("trajectory.zig");

/// An Action adapter reports only the test outcome. It must not write production
/// state; callers should pass an ephemeral fixture or isolated test double.
pub const ActionResult = enum { passed, failed };
pub const ActionRunner = *const fn (context: *anyopaque, edge_index: usize, edge: trajectory.Edge) ActionResult;
pub const InvariantOracle = *const fn (context: *anyopaque, terminal_node: trajectory.NodeId) bool;

pub const Report = struct {
    trajectories_run: usize = 0,
    trajectories_passed: usize = 0,
    attempted_edges: []bool,
    passed_edges: []bool,
    failed_edges: []bool,
    invariant_failures: []trajectory.NodeId,

    pub fn deinit(self: *Report, allocator: std.mem.Allocator) void {
        allocator.free(self.attempted_edges);
        allocator.free(self.passed_edges);
        allocator.free(self.failed_edges);
        allocator.free(self.invariant_failures);
    }
    pub fn attemptedEdgeCoverage(self: Report) f64 {
        return coverage(self.attempted_edges);
    }
    pub fn passedEdgeCoverage(self: Report) f64 {
        return coverage(self.passed_edges);
    }
    pub fn failedEdgeCount(self: Report) usize {
        return countTrue(self.failed_edges);
    }
    pub fn unattemptedEdgeCount(self: Report) usize {
        return self.attempted_edges.len - countTrue(self.attempted_edges);
    }
    fn coverage(bits: []const bool) f64 {
        if (bits.len == 0) return 1.0;
        return @as(f64, @floatFromInt(countTrue(bits))) / @as(f64, @floatFromInt(bits.len));
    }
    fn countTrue(bits: []const bool) usize {
        var count: usize = 0;
        for (bits) |bit| if (bit) {
            count += 1;
        };
        return count;
    }
};

/// Runs each generated trajectory through caller-supplied test adapters.
/// A failed edge stops only that trajectory; later paths still run. The
/// invariant oracle runs only after every edge of a terminal path passes.
pub fn execute(
    allocator: std.mem.Allocator,
    plan: trajectory.Plan,
    graph: trajectory.Graph,
    context: *anyopaque,
    action_runner: ActionRunner,
    invariant_oracle: InvariantOracle,
) !Report {
    const attempted_edges = try allocator.alloc(bool, graph.edges.len);
    errdefer allocator.free(attempted_edges);
    const passed_edges = try allocator.alloc(bool, graph.edges.len);
    errdefer allocator.free(passed_edges);
    const failed_edges = try allocator.alloc(bool, graph.edges.len);
    errdefer allocator.free(failed_edges);
    var report = Report{
        .attempted_edges = attempted_edges,
        .passed_edges = passed_edges,
        .failed_edges = failed_edges,
        .invariant_failures = &.{},
    };
    @memset(report.attempted_edges, false);
    @memset(report.passed_edges, false);
    @memset(report.failed_edges, false);

    var invariant_failures = std.ArrayList(trajectory.NodeId).empty;
    errdefer invariant_failures.deinit(allocator);
    for (plan.trajectories) |path| {
        report.trajectories_run += 1;
        var path_passed = true;
        for (path.edges) |edge_index| {
            if (edge_index >= graph.edges.len) return error.InvalidTrajectoryEdge;
            report.attempted_edges[edge_index] = true;
            if (action_runner(context, edge_index, graph.edges[edge_index]) == .failed) {
                report.failed_edges[edge_index] = true;
                path_passed = false;
                break;
            }
            report.passed_edges[edge_index] = true;
        }
        if (path_passed and path.terminal and path.nodes.len > 0) {
            const terminal_node = path.nodes[path.nodes.len - 1];
            if (terminal_node >= graph.nodes.len) return error.InvalidTrajectoryNode;
            if (!invariant_oracle(context, terminal_node)) {
                try invariant_failures.append(allocator, terminal_node);
                path_passed = false;
            }
        }
        if (path_passed) report.trajectories_passed += 1;
    }
    report.invariant_failures = try invariant_failures.toOwnedSlice(allocator);
    return report;
}

const TestState = struct {
    failed_edge: ?usize = null,
    invariant_holds: bool = true,
    invariant_calls: usize = 0,
};
fn testActionRunner(raw: *anyopaque, edge_index: usize, edge: trajectory.Edge) ActionResult {
    _ = edge;
    const state: *TestState = @ptrCast(@alignCast(raw));
    return if (state.failed_edge != null and state.failed_edge.? == edge_index) .failed else .passed;
}
fn testInvariantOracle(raw: *anyopaque, terminal_node: trajectory.NodeId) bool {
    _ = terminal_node;
    const state: *TestState = @ptrCast(@alignCast(raw));
    state.invariant_calls += 1;
    return state.invariant_holds;
}

test "executes terminal trajectories and reports edge and invariant coverage" {
    const allocator = std.testing.allocator;
    const nodes = [_]trajectory.Node{ .{ .name = "START" }, .{ .name = "ACCEPT", .terminal = true }, .{ .name = "REJECT", .terminal = true } };
    const edges = [_]trajectory.Edge{ .{ .from = 0, .to = 1, .label = "accept" }, .{ .from = 0, .to = 2, .label = "reject" } };
    const graph = trajectory.Graph{ .nodes = &nodes, .edges = &edges, .start = 0 };
    var plan = try trajectory.generate(allocator, graph, .{});
    defer plan.deinit(allocator);
    var state = TestState{};
    var report = try execute(allocator, plan, graph, @ptrCast(&state), testActionRunner, testInvariantOracle);
    defer report.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 2), report.trajectories_run);
    try std.testing.expectEqual(@as(usize, 2), report.trajectories_passed);
    try std.testing.expectEqual(@as(usize, 0), report.failedEdgeCount());
    try std.testing.expectEqual(@as(usize, 0), report.unattemptedEdgeCount());
    try std.testing.expectEqual(@as(usize, 2), state.invariant_calls);
    try std.testing.expectEqual(@as(f64, 1.0), report.attemptedEdgeCoverage());
}

test "failed Action is reported and skips its terminal invariant" {
    const allocator = std.testing.allocator;
    const nodes = [_]trajectory.Node{ .{ .name = "START" }, .{ .name = "DONE", .terminal = true } };
    const edges = [_]trajectory.Edge{.{ .from = 0, .to = 1, .label = "execute" }};
    const graph = trajectory.Graph{ .nodes = &nodes, .edges = &edges, .start = 0 };
    var plan = try trajectory.generate(allocator, graph, .{});
    defer plan.deinit(allocator);
    var state = TestState{ .failed_edge = 0 };
    var report = try execute(allocator, plan, graph, @ptrCast(&state), testActionRunner, testInvariantOracle);
    defer report.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 0), report.trajectories_passed);
    try std.testing.expectEqual(@as(usize, 1), report.failedEdgeCount());
    try std.testing.expectEqual(@as(usize, 0), state.invariant_calls);
}

test "invariant failure fails a trajectory after successful Actions" {
    const allocator = std.testing.allocator;
    const nodes = [_]trajectory.Node{ .{ .name = "START" }, .{ .name = "DONE", .terminal = true } };
    const edges = [_]trajectory.Edge{.{ .from = 0, .to = 1, .label = "execute" }};
    const graph = trajectory.Graph{ .nodes = &nodes, .edges = &edges, .start = 0 };
    var plan = try trajectory.generate(allocator, graph, .{});
    defer plan.deinit(allocator);
    var state = TestState{ .invariant_holds = false };
    var report = try execute(allocator, plan, graph, @ptrCast(&state), testActionRunner, testInvariantOracle);
    defer report.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 0), report.trajectories_passed);
    try std.testing.expectEqual(@as(usize, 1), report.invariant_failures.len);
    try std.testing.expectEqual(@as(trajectory.NodeId, 1), report.invariant_failures[0]);
}
