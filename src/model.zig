const std = @import("std");

pub const ValueKind = enum { string, integer, boolean };

pub const StringConstraints = struct {
    min_len: ?usize = null,
    max_len: ?usize = null,
};

pub const IntConstraints = struct {
    min: ?i64 = null,
    max: ?i64 = null,
};

pub const Constraints = union(ValueKind) {
    string: StringConstraints,
    integer: IntConstraints,
    boolean: void,
};

pub const ParameterSpec = struct {
    name: []const u8,
    constraints: Constraints,
};

pub const FunctionSpec = struct {
    name: []const u8,
    parameters: []const ParameterSpec,
};

pub const Value = union(ValueKind) {
    string: []const u8,
    integer: i64,
    boolean: bool,
};

pub const Argument = struct {
    name: []const u8,
    value: Value,
};

pub const CaseKind = enum { valid, boundary, invalid };

pub const TestCase = struct {
    name: []const u8,
    kind: CaseKind,
    invalid_parameter: ?[]const u8 = null,
    arguments: []Argument,
};

pub const ExecutionPolicy = struct {
    test: bool = true,
    ephemeral: bool = true,
    persist_payload: bool = false,
    persist_events: bool = false,
};

pub const TestPlan = struct {
    function_name: []const u8,
    seed: u64,
    policy: ExecutionPolicy = .{},
    cases: []TestCase,

    pub fn deinit(self: *TestPlan, allocator: std.mem.Allocator) void {
        for (self.cases) |case| {
            allocator.free(case.name);
            for (case.arguments) |arg| switch (arg.value) {
                .string => |s| allocator.free(s),
                else => {},
            };
            allocator.free(case.arguments);
        }
        allocator.free(self.cases);
    }
};
