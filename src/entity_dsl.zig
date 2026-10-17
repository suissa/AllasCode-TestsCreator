const std = @import("std");

pub const ParseError = error{
    EmptySource,
    MissingEntity,
    DuplicateEntity,
    MissingInput,
    MissingRun,
    MissingExpectation,
    InvalidDeclaration,
    InvalidInput,
    InvalidRun,
    InvalidExpectation,
    InvalidInteger,
    InvalidBoolean,
    UnexpectedDeclaration,
    MissingArgument,
};

pub const ValueKind = enum { string, integer, boolean };

pub const Value = union(ValueKind) {
    string: []const u8,
    integer: i64,
    boolean: bool,
};

pub const Input = struct {
    name: []const u8,
    value: Value,
};

pub const Run = struct {
    action: []const u8,
    arguments: []const []const u8,
};

pub const Expectation = struct {
    predicate: []const u8,
};

pub const Scenario = struct {
    entity: []const u8,
    inputs: []Input,
    runs: []Run,
    expectations: []Expectation,

    pub fn deinit(self: *Scenario, allocator: std.mem.Allocator) void {
        for (self.inputs) |input| switch (input.value) {
            .string => |value| allocator.free(value),
            else => {},
        };
        allocator.free(self.inputs);

        for (self.runs) |run| allocator.free(run.arguments);
        allocator.free(self.runs);
        allocator.free(self.expectations);
    }
};

fn trim(value: []const u8) []const u8 {
    return std.mem.trim(u8, value, " \t\r");
}

fn parseValue(allocator: std.mem.Allocator, raw: []const u8) !Value {
    const value = trim(raw);
    if (value.len >= 2 and value[0] == '"' and value[value.len - 1] == '"') {
        return .{ .string = try allocator.dupe(u8, value[1 .. value.len - 1]) };
    }
    if (std.mem.eql(u8, value, "true")) return .{ .boolean = true };
    if (std.mem.eql(u8, value, "false")) return .{ .boolean = false };
    return .{ .integer = std.fmt.parseInt(i64, value, 10) catch
        return .{ .string = try allocator.dupe(u8, value) } };
}

fn parseRunArguments(allocator: std.mem.Allocator, raw: []const u8) ![]const []const u8 {
    const args = trim(raw);
    if (args.len == 0) return try allocator.alloc([]const u8, 0);

    var list = std.ArrayList([]const u8).empty;
    errdefer list.deinit(allocator);
    var iterator = std.mem.splitScalar(u8, args, ',');
    while (iterator.next()) |item| {
        const argument = trim(item);
        if (argument.len == 0) return ParseError.MissingArgument;
        try list.append(allocator, argument);
    }
    return try list.toOwnedSlice(allocator);
}

fn parseInput(allocator: std.mem.Allocator, line: []const u8) !Input {
    const prefix = "Input ";
    if (!std.mem.startsWith(u8, line, prefix)) return ParseError.InvalidInput;
    const assignment = std.mem.indexOfScalar(u8, line[prefix.len..], '=') orelse return ParseError.InvalidInput;
    const name = trim(line[prefix.len .. prefix.len + assignment]);
    const raw_value = trim(line[prefix.len + assignment + 1 ..]);
    if (name.len == 0 or raw_value.len == 0) return ParseError.InvalidInput;
    return .{ .name = name, .value = try parseValue(allocator, raw_value) };
}

fn parseRun(allocator: std.mem.Allocator, line: []const u8) !Run {
    const prefix = "Run ";
    if (!std.mem.startsWith(u8, line, prefix)) return ParseError.InvalidRun;
    const expression = trim(line[prefix.len..]);
    const open = std.mem.indexOfScalar(u8, expression, '(') orelse return ParseError.InvalidRun;
    if (expression.len < open + 2 or expression[expression.len - 1] != ')') return ParseError.InvalidRun;
    const action = trim(expression[0..open]);
    if (action.len == 0) return ParseError.InvalidRun;
    const arguments = try parseRunArguments(allocator, expression[open + 1 .. expression.len - 1]);
    return .{ .action = action, .arguments = arguments };
}

fn parseExpectation(line: []const u8) !Expectation {
    const prefix = "Expect ";
    if (!std.mem.startsWith(u8, line, prefix)) return ParseError.InvalidExpectation;
    const predicate = trim(line[prefix.len..]);
    if (predicate.len == 0) return ParseError.InvalidExpectation;
    return .{ .predicate = predicate };
}

/// Parses the minimal Entity Driven Testing surface.
///
/// Example:
/// Entity: Person
/// Input cpf = 04864713901
/// Run validate(cpf)
/// Expect isTruth
///
/// The parser only creates data. It never executes the Action or interprets the
/// expectation as an assertion; the runtime remains the authority for outcomes.
pub fn parse(allocator: std.mem.Allocator, source: []const u8) !Scenario {
    var entity: []const u8 = "";
    var inputs = std.ArrayList(Input).empty;
    var runs = std.ArrayList(Run).empty;
    var expectations = std.ArrayList(Expectation).empty;
    errdefer {
        for (inputs.items) |input| switch (input.value) {
            .string => |value| allocator.free(value),
            else => {},
        };
        inputs.deinit(allocator);
        for (runs.items) |run| allocator.free(run.arguments);
        runs.deinit(allocator);
        expectations.deinit(allocator);
    }

    var lines = std.mem.splitScalar(u8, source, '\n');
    while (lines.next()) |raw_line| {
        const line = trim(raw_line);
        if (line.len == 0 or line[0] == '#') continue;

        if (std.mem.startsWith(u8, line, "Entity:")) {
            if (entity.len != 0) return ParseError.DuplicateEntity;
            entity = trim(line["Entity:".len..]);
            if (entity.len == 0) return ParseError.MissingEntity;
        } else if (std.mem.startsWith(u8, line, "Input ")) {
            try inputs.append(allocator, try parseInput(allocator, line));
        } else if (std.mem.startsWith(u8, line, "Run ")) {
            try runs.append(allocator, try parseRun(allocator, line));
        } else if (std.mem.startsWith(u8, line, "Expect ")) {
            try expectations.append(allocator, try parseExpectation(line));
        } else {
            return ParseError.UnexpectedDeclaration;
        }
    }

    if (entity.len == 0) return ParseError.MissingEntity;
    if (inputs.items.len == 0) return ParseError.MissingInput;
    if (runs.items.len == 0) return ParseError.MissingRun;
    if (expectations.items.len == 0) return ParseError.MissingExpectation;

    return .{
        .entity = entity,
        .inputs = try inputs.toOwnedSlice(allocator),
        .runs = try runs.toOwnedSlice(allocator),
        .expectations = try expectations.toOwnedSlice(allocator),
    };
}

test "parses an entity scenario" {
    const allocator = std.testing.allocator;
    var scenario = try parse(allocator,
        \Entity: Person
        \Input cpf = 04864713901
        \Run validate(cpf)
        \Expect isTruth
    );
    defer scenario.deinit(allocator);

    try std.testing.expectEqualStrings("Person", scenario.entity);
    try std.testing.expectEqual(@as(usize, 1), scenario.inputs.len);
    try std.testing.expectEqualStrings("cpf", scenario.inputs[0].name);
    try std.testing.expectEqual(@as(i64, 4_864_713_901), scenario.inputs[0].value.integer);
    try std.testing.expectEqualStrings("validate", scenario.runs[0].action);
    try std.testing.expectEqual(@as(usize, 1), scenario.runs[0].arguments.len);
    try std.testing.expectEqualStrings("cpf", scenario.runs[0].arguments[0]);
    try std.testing.expectEqualStrings("isTruth", scenario.expectations[0].predicate);
}

test "supports string and boolean inputs" {
    const allocator = std.testing.allocator;
    var scenario = try parse(allocator,
        \Entity: Person
        \Input name = "Ada"
        \Input active = true
        \Run validate(name, active)
        \Expect isTruth
    );
    defer scenario.deinit(allocator);

    try std.testing.expectEqualStrings("Ada", scenario.inputs[0].value.string);
    try std.testing.expect(scenario.inputs[1].value.boolean);
    try std.testing.expectEqual(@as(usize, 2), scenario.runs[0].arguments.len);
}

test "preserves arbitrary expectation expressions for later semantic lowering" {
    const allocator = std.testing.allocator;
    var scenario = try parse(allocator,
        \Entity: Order
        \Input total = 100
        \Run calculate(total)
        \Expect equals(100)
    );
    defer scenario.deinit(allocator);

    try std.testing.expectEqualStrings("equals(100)", scenario.expectations[0].predicate);
}

test "rejects incomplete entity scenarios" {
    const allocator = std.testing.allocator;
    try std.testing.expectError(ParseError.MissingRun, parse(allocator,
        \Entity: Person
        \Input cpf = 123
        \Expect isTruth
    ));
}

test "rejects unknown declarations" {
    const allocator = std.testing.allocator;
    try std.testing.expectError(ParseError.UnexpectedDeclaration, parse(allocator,
        \Entity: Person
        \Given something
        \Input cpf = 123
        \Run validate(cpf)
        \Expect isTruth
    ));
}
