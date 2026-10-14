const std = @import("std");

pub const NodeId = usize;
pub const Node = struct { name: []const u8, terminal: bool = false };
pub const Edge = struct { from: NodeId, to: NodeId, label: []const u8 };
pub const Graph = struct { nodes: []const Node, edges: []const Edge, start: NodeId };
pub const Options = struct {
    max_depth: usize = 32,
    stop_on_cycle: bool = true,
    terminal_paths_only: bool = true,
};
pub const Trajectory = struct { nodes: []NodeId, edges: []usize, terminal: bool };
pub const Plan = struct {
    trajectories: []Trajectory,
    covered_edges: []bool,
    uncovered_edges: []usize,
    pub fn deinit(self: *Plan, allocator: std.mem.Allocator) void {
        for (self.trajectories) |path| {
            allocator.free(path.nodes);
            allocator.free(path.edges);
        }
        allocator.free(self.trajectories);
        allocator.free(self.covered_edges);
        allocator.free(self.uncovered_edges);
    }
    pub fn edgeCoverage(self: Plan) f64 {
        if (self.covered_edges.len == 0) return 1.0;
        var covered: usize = 0;
        for (self.covered_edges) |hit| if (hit) { covered += 1; };
        return @as(f64, @floatFromInt(covered)) / @as(f64, @floatFromInt(self.covered_edges.len));
    }
};
pub const Error = error{ InvalidStart, InvalidEdge, InvalidOptions, NoTerminalTrajectory };

pub fn generate(allocator: std.mem.Allocator, graph: Graph, options: Options) !Plan {
    if (graph.start >= graph.nodes.len) return Error.InvalidStart;
    if (options.max_depth == 0) return Error.InvalidOptions;
    for (graph.edges) |edge| {
        if (edge.from >= graph.nodes.len or edge.to >= graph.nodes.len) return Error.InvalidEdge;
    }
    var context = Context{
        .allocator = allocator, .graph = graph, .options = options,
        .paths = std.ArrayList(Trajectory).empty,
        .edge_hits = try allocator.alloc(bool, graph.edges.len),
    };
    errdefer {
        for (context.paths.items) |path| {
            allocator.free(path.nodes);
            allocator.free(path.edges);
        }
        context.paths.deinit(allocator);
        allocator.free(context.edge_hits);
    }
    @memset(context.edge_hits, false);
    var node_path = std.ArrayList(NodeId).empty;
    defer node_path.deinit(allocator);
    var edge_path = std.ArrayList(usize).empty;
    defer edge_path.deinit(allocator);
    try node_path.append(allocator, graph.start);
    try context.walk(graph.start, &node_path, &edge_path, 0);
    if (options.terminal_paths_only and context.paths.items.len == 0) return Error.NoTerminalTrajectory;
    var uncovered = std.ArrayList(usize).empty;
    errdefer uncovered.deinit(allocator);
    for (context.edge_hits, 0..) |hit, i| {
        if (!hit) try uncovered.append(allocator, i);
    }
    return .{
        .trajectories = try context.paths.toOwnedSlice(allocator),
        .covered_edges = context.edge_hits,
        .uncovered_edges = try uncovered.toOwnedSlice(allocator),
    };
}

const Context = struct {
    allocator: std.mem.Allocator, graph: Graph, options: Options,
    paths: std.ArrayList(Trajectory), edge_hits: []bool,
    fn walk(self: *Context, current: NodeId, nodes: *std.ArrayList(NodeId), edges: *std.ArrayList(usize), depth: usize) anyerror!void {
        if (self.graph.nodes[current].terminal) {
            try self.emit(nodes, edges, true);
            return;
        }
        if (depth >= self.options.max_depth) {
            if (!self.options.terminal_paths_only) try self.emit(nodes, edges, false);
            return;
        }
        var has_outgoing = false;
        for (self.graph.edges, 0..) |edge, edge_index| {
            if (edge.from != current) continue;
            has_outgoing = true;
            if (self.options.stop_on_cycle and contains(nodes.items, edge.to)) {
                continue;
            }
            try edges.append(self.allocator, edge_index);
            try nodes.append(self.allocator, edge.to);
            try self.walk(edge.to, nodes, edges, depth + 1);
            _ = nodes.pop();
            _ = edges.pop();
        }
        if (!has_outgoing and !self.options.terminal_paths_only) try self.emit(nodes, edges, false);
    }
    fn emit(self: *Context, nodes: *std.ArrayList(NodeId), edges: *std.ArrayList(usize), terminal: bool) !void {
        const node_copy = try self.allocator.dupe(NodeId, nodes.items);
        errdefer self.allocator.free(node_copy);
        const edge_copy = try self.allocator.dupe(usize, edges.items);
        errdefer self.allocator.free(edge_copy);
        try self.paths.append(self.allocator, .{ .nodes = node_copy, .edges = edge_copy, .terminal = terminal });
        // Coverage means an edge appears in an emitted trajectory, not merely that DFS visited it.
        for (edges.items) |edge_index| self.edge_hits[edge_index] = true;
    }
};
fn contains(items: []const NodeId, target: NodeId) bool {
    for (items) |item| if (item == target) return true;
    return false;
}

test "enumerates each terminal branch to its endpoint" {
    const allocator = std.testing.allocator;
    const nodes = [_]Node{ .{ .name = "START" }, .{ .name = "A" }, .{ .name = "SUCCESS", .terminal = true }, .{ .name = "RECOVER" }, .{ .name = "ABORT", .terminal = true } };
    const edges = [_]Edge{
        .{ .from = 0, .to = 1, .label = "begin" }, .{ .from = 1, .to = 2, .label = "success" },
        .{ .from = 1, .to = 3, .label = "failure" }, .{ .from = 3, .to = 2, .label = "retry" },
        .{ .from = 3, .to = 4, .label = "abort" },
    };
    var plan = try generate(allocator, .{ .nodes = &nodes, .edges = &edges, .start = 0 }, .{});
    defer plan.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 3), plan.trajectories.len);
    try std.testing.expectEqual(@as(usize, 0), plan.uncovered_edges.len);
    for (plan.trajectories) |path| try std.testing.expect(path.terminal);
}
test "cycles are bounded and transitions are accounted for" {
    const allocator = std.testing.allocator;
    const nodes = [_]Node{ .{ .name = "START" }, .{ .name = "RETRY" }, .{ .name = "DONE", .terminal = true } };
    const edges = [_]Edge{ .{ .from = 0, .to = 1, .label = "start" }, .{ .from = 1, .to = 1, .label = "retry" }, .{ .from = 1, .to = 2, .label = "finish" } };
    var plan = try generate(allocator, .{ .nodes = &nodes, .edges = &edges, .start = 0 }, .{});
    defer plan.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 1), plan.trajectories.len);
    try std.testing.expectEqual(@as(usize, 1), plan.uncovered_edges.len);
    try std.testing.expectEqual(@as(usize, 1), plan.uncovered_edges[0]);
}
test "reports unreachable transitions" {
    const allocator = std.testing.allocator;
    const nodes = [_]Node{ .{ .name = "START" }, .{ .name = "DONE", .terminal = true }, .{ .name = "UNREACHABLE" } };
    const edges = [_]Edge{ .{ .from = 0, .to = 1, .label = "finish" }, .{ .from = 2, .to = 1, .label = "never" } };
    var plan = try generate(allocator, .{ .nodes = &nodes, .edges = &edges, .start = 0 }, .{});
    defer plan.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 1), plan.uncovered_edges.len);
    try std.testing.expectEqual(@as(usize, 1), plan.uncovered_edges[0]);
}
test "does not count dead-end transitions without an emitted trajectory" {
    const allocator = std.testing.allocator;
    const nodes = [_]Node{ .{ .name = "START" }, .{ .name = "DONE", .terminal = true }, .{ .name = "DEAD_END" } };
    const edges = [_]Edge{ .{ .from = 0, .to = 1, .label = "finish" }, .{ .from = 0, .to = 2, .label = "dead-end" } };
    var plan = try generate(allocator, .{ .nodes = &nodes, .edges = &edges, .start = 0 }, .{});
    defer plan.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 1), plan.trajectories.len);
    try std.testing.expectEqual(@as(usize, 1), plan.uncovered_edges.len);
    try std.testing.expectEqual(@as(usize, 1), plan.uncovered_edges[0]);
}

test "rejects invalid graph start and zero depth" {
    const allocator = std.testing.allocator;
    const nodes = [_]Node{.{ .name = "DONE", .terminal = true }};
    const edges = [_]Edge{};
    try std.testing.expectError(Error.InvalidStart, generate(allocator, .{ .nodes = &nodes, .edges = &edges, .start = 3 }, .{}));
    try std.testing.expectError(Error.InvalidOptions, generate(allocator, .{ .nodes = &nodes, .edges = &edges, .start = 0 }, .{ .max_depth = 0 }));
}
