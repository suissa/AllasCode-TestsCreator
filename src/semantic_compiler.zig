const std = @import("std");

const max_cases = 128;
const max_output = 65536;

pub const TestKind = enum { unit, load, stress, chaos, security };

const Case = struct {
    kind: TestKind,
    name: []const u8,
    subject: []const u8,
    input: []const u8,
    invariants: []const u8,
};

const Declaration = struct {
    suite: []const u8 = "",
    agent: []const u8 = "",
    intent: []const u8 = "",
    cases: [max_cases]Case = undefined,
    case_count: usize = 0,
};

const YamlConfig = struct {
    suite: []const u8 = "",
    agent: []const u8 = "",
    intent: []const u8 = "",
    unit_max_events: usize = 64,
    load_repetitions: usize = 8,
    load_max_events: usize = 256,
    stress_workers: usize = 4,
    stress_duration_ms: usize = 1000,
    stress_max_failures: usize = 0,
    chaos_faults: []const u8 = "",
    chaos_recovery: []const u8 = "",
    security_capabilities: []const u8 = "",
    security_denials: []const u8 = "",
};

pub const Buffer = struct {
    bytes: [max_output]u8 = undefined,
    len: usize = 0,

    fn raw(self: *Buffer, value: []const u8) void {
        if (self.len + value.len > max_output) @compileError("generated JSON exceeds compiler buffer");
        @memcpy(self.bytes[self.len .. self.len + value.len], value);
        self.len += value.len;
    }

    fn jsonString(self: *Buffer, value: []const u8) void {
        self.raw("\"");
        for (value) |character| {
            switch (character) {
                '"' => self.raw("\\\""),
                '\\' => self.raw("\\\\"),
                '\n' => self.raw("\\n"),
                '\r' => self.raw("\\r"),
                '\t' => self.raw("\\t"),
                else => {
                    self.bytes[self.len] = character;
                    self.len += 1;
                },
            }
        }
        self.raw("\"");
    }

    fn key(self: *Buffer, name: []const u8, value: []const u8) void {
        self.jsonString(name);
        self.raw(":");
        self.jsonString(value);
    }

    fn number(self: *Buffer, value: usize) void {
        var temporary: [32]u8 = undefined;
        var cursor = temporary.len;
        var remaining = value;
        if (remaining == 0) {
            self.raw("0");
            return;
        }
        while (remaining > 0) {
            cursor -= 1;
            temporary[cursor] = @intCast('0' + remaining % 10);
            remaining /= 10;
        }
        self.raw(temporary[cursor..]);
    }

    fn boolean(self: *Buffer, value: bool) void {
        self.raw(if (value) "true" else "false");
    }

    fn comma(self: *Buffer, first: *bool) void {
        if (!first.*) self.raw(",");
        first.* = false;
    }

    pub fn slice(self: *const Buffer) []const u8 {
        return self.bytes[0..self.len];
    }
};

fn tokenAt(line: []const u8, wanted: usize) []const u8 {
    var iterator = std.mem.tokenizeAny(u8, line, " \t\r");
    var index: usize = 0;
    while (iterator.next()) |token| {
        if (index == wanted) return token;
        index += 1;
    }
    return "";
}

fn valueToken(line: []const u8, key_name: []const u8) []const u8 {
    var iterator = std.mem.tokenizeAny(u8, line, " \t\r");
    _ = iterator.next();
    _ = iterator.next();
    while (iterator.next()) |token| {
        if (token.len > key_name.len and std.mem.startsWith(u8, token, key_name) and token[key_name.len] == '=')
            return token[key_name.len + 1 ..];
    }
    return "";
}

fn parseKind(token: []const u8) ?TestKind {
    if (std.mem.eql(u8, token, "unit")) return .unit;
    if (std.mem.eql(u8, token, "load")) return .load;
    if (std.mem.eql(u8, token, "stress")) return .stress;
    if (std.mem.eql(u8, token, "chaos")) return .chaos;
    if (std.mem.eql(u8, token, "security")) return .security;
    return null;
}

fn parseDeclaration(comptime source: []const u8) Declaration {
    var result = Declaration{};
    var lines = std.mem.splitScalar(u8, source, '\n');
    while (lines.next()) |raw_line| {
        const line = std.mem.trim(u8, raw_line, " \t\r");
        if (line.len == 0 or line[0] == '#') continue;
        const first = tokenAt(line, 0);
        if (std.mem.eql(u8, first, "suite")) {
            result.suite = tokenAt(line, 1);
        } else if (std.mem.eql(u8, first, "agent")) {
            result.agent = tokenAt(line, 1);
        } else if (std.mem.eql(u8, first, "intent")) {
            result.intent = tokenAt(line, 1);
        } else if (parseKind(first)) |kind| {
            if (result.case_count >= max_cases) @compileError("too many semantic test declarations");
            result.cases[result.case_count] = .{
                .kind = kind,
                .name = tokenAt(line, 1),
                .subject = valueToken(line, "subject"),
                .input = valueToken(line, "input"),
                .invariants = valueToken(line, "invariants"),
            };
            result.case_count += 1;
        } else {
            @compileError("unknown semantic DSL declaration");
        }
    }
    return result;
}

fn parseNumber(value: []const u8, key_name: []const u8) usize {
    return std.fmt.parseInt(usize, value, 10) catch @compileError(key_name ++ " must be an unsigned integer");
}

fn parseYaml(comptime source: []const u8) YamlConfig {
    var result = YamlConfig{};
    var lines = std.mem.splitScalar(u8, source, '\n');
    while (lines.next()) |raw_line| {
        const line = std.mem.trim(u8, raw_line, " \t\r");
        if (line.len == 0 or line[0] == '#') continue;
        const separator = std.mem.indexOfScalar(u8, line, ':') orelse @compileError("YAML line must contain ':'");
        const key_name = std.mem.trim(u8, line[0..separator], " \t");
        const value = std.mem.trim(u8, line[separator + 1 ..], " \t\"");
        if (std.mem.eql(u8, key_name, "suite")) result.suite = value
        else if (std.mem.eql(u8, key_name, "agent")) result.agent = value
        else if (std.mem.eql(u8, key_name, "intent")) result.intent = value
        else if (std.mem.eql(u8, key_name, "unit_max_events")) result.unit_max_events = parseNumber(value, key_name)
        else if (std.mem.eql(u8, key_name, "load_repetitions")) result.load_repetitions = parseNumber(value, key_name)
        else if (std.mem.eql(u8, key_name, "load_max_events")) result.load_max_events = parseNumber(value, key_name)
        else if (std.mem.eql(u8, key_name, "stress_workers")) result.stress_workers = parseNumber(value, key_name)
        else if (std.mem.eql(u8, key_name, "stress_duration_ms")) result.stress_duration_ms = parseNumber(value, key_name)
        else if (std.mem.eql(u8, key_name, "stress_max_failures")) result.stress_max_failures = parseNumber(value, key_name)
        else if (std.mem.eql(u8, key_name, "chaos_faults")) result.chaos_faults = value
        else if (std.mem.eql(u8, key_name, "chaos_recovery")) result.chaos_recovery = value
        else if (std.mem.eql(u8, key_name, "security_capabilities")) result.security_capabilities = value
        else if (std.mem.eql(u8, key_name, "security_denials")) result.security_denials = value
        else @compileError("unknown YAML configuration key");
    }
    return result;
}

fn hasKind(declaration: Declaration, kind: TestKind) bool {
    for (declaration.cases[0..declaration.case_count]) |test_case| {
        if (test_case.kind == kind) return true;
    }
    return false;
}

fn validate(declaration: Declaration, config: YamlConfig) void {
    if (declaration.suite.len == 0 or declaration.agent.len == 0 or declaration.intent.len == 0)
        @compileError("DSL must declare suite, agent and intent");
    if (config.suite.len == 0 or config.agent.len == 0 or config.intent.len == 0)
        @compileError("YAML must declare suite, agent and intent");
    if (!std.mem.eql(u8, declaration.suite, config.suite) or
        !std.mem.eql(u8, declaration.agent, config.agent) or
        !std.mem.eql(u8, declaration.intent, config.intent))
        @compileError("DSL identity and YAML identity must match");
    for ([_]TestKind{ .unit, .load, .stress, .chaos, .security }) |kind| {
        if (!hasKind(declaration, kind)) @compileError("DSL must declare every canonical test type");
    }
    if (config.load_repetitions == 0 or config.load_max_events == 0 or config.stress_workers == 0 or config.stress_duration_ms == 0)
        @compileError("load and stress configuration must be non-zero");
}

fn appendCsvArray(output: *Buffer, value: []const u8) void {
    output.raw("[");
    var first = true;
    var iterator = std.mem.tokenizeAny(u8, value, ",");
    while (iterator.next()) |entry| {
        output.comma(&first);
        output.jsonString(std.mem.trim(u8, entry, " \t"));
    }
    output.raw("]");
}

fn appendCommon(output: *Buffer, test_case: Case) void {
    output.key("name", test_case.name);
    output.raw(",");
    output.key("subject", test_case.subject);
    output.raw(",");
    output.key("input", test_case.input);
    output.raw(",");
    output.jsonString("invariants");
    output.raw(":");
    appendCsvArray(output, test_case.invariants);
}

fn appendTest(output: *Buffer, test_case: Case, config: YamlConfig) void {
    output.raw("{");
    output.key("schema", switch (test_case.kind) {
        .unit => "pcore.test.unit.v1", .load => "pcore.test.load.v1",
        .stress => "pcore.test.stress.v1", .chaos => "pcore.test.chaos.v1",
        .security => "pcore.test.security.v1",
    });
    output.raw(",");
    output.key("kind", @tagName(test_case.kind));
    output.raw(",");
    appendCommon(output, test_case);
    switch (test_case.kind) {
        .unit => {
            output.raw(","); output.key("oracle", "runtime-owned");
            output.raw(","); output.jsonString("max_events"); output.raw(":"); output.number(config.unit_max_events);
        },
        .load => {
            output.raw(","); output.jsonString("repetitions"); output.raw(":"); output.number(config.load_repetitions);
            output.raw(","); output.jsonString("max_events"); output.raw(":"); output.number(config.load_max_events);
            output.raw(","); output.key("settlement", "idempotent-replay");
        },
        .stress => {
            output.raw(","); output.jsonString("workers"); output.raw(":"); output.number(config.stress_workers);
            output.raw(","); output.jsonString("duration_ms"); output.raw(":"); output.number(config.stress_duration_ms);
            output.raw(","); output.jsonString("max_failures"); output.raw(":"); output.number(config.stress_max_failures);
            output.raw(","); output.key("scheduling", "bounded-fairness");
        },
        .chaos => {
            output.raw(","); output.jsonString("faults"); output.raw(":"); appendCsvArray(output, config.chaos_faults);
            output.raw(","); output.key("recovery", config.chaos_recovery);
            output.raw(","); output.jsonString("replay_required"); output.raw(":"); output.boolean(true);
        },
        .security => {
            output.raw(","); output.jsonString("capabilities"); output.raw(":"); appendCsvArray(output, config.security_capabilities);
            output.raw(","); output.jsonString("denials"); output.raw(":"); appendCsvArray(output, config.security_denials);
            output.raw(","); output.key("secret_handling", "never-export");
            output.raw(","); output.key("terminal_authority", "runtime-owned");
        },
    }
    output.raw("}");
}

pub fn compile(comptime declaration_source: []const u8, comptime yaml_source: []const u8) Buffer {
    @setEvalBranchQuota(100_000);
    const declaration = parseDeclaration(declaration_source);
    const config = parseYaml(yaml_source);
    validate(declaration, config);
    var output = Buffer{};
    output.raw("{");
    output.key("schema", "pcore.test.bundle.v1");
    output.raw(",");
    output.key("suite", config.suite);
    output.raw(",");
    output.key("agent", config.agent);
    output.raw(",");
    output.key("intent", config.intent);
    output.raw(",");
    output.jsonString("tests");
    output.raw(":[");
    var first = true;
    for (declaration.cases[0..declaration.case_count]) |test_case| {
        output.comma(&first);
        appendTest(&output, test_case, config);
    }
    output.raw("]}");
    return output;
}

const sample_declaration =
    \suite DynamicDataQuality
    \agent ConfiguredDataAgent
    \intent ConfiguredDynamicDataIntent
    \unit Data.InspectValueShape subject=action input=records invariants=bounded-local-input,runtime-owned-terminal,idempotent
    \load Data.InspectValueShape subject=action input=records invariants=bounded-local-input,idempotent,replay-stable
    \stress Data.AggregateRecords subject=action input=records invariants=bounded-local-input,bounded-memory,fair-scheduling
    \chaos Data.MaterializeProjection subject=action input=records invariants=restart-safe,resume-safe,replay-stable
    \security Data.MaterializeProjection subject=action input=records invariants=no-network,no-arbitrary-code,no-source-mutation,no-direct-terminal
;

const sample_config =
    \suite: DynamicDataQuality
    \agent: ConfiguredDataAgent
    \intent: ConfiguredDynamicDataIntent
    \unit_max_events: 64
    \load_repetitions: 8
    \load_max_events: 256
    \stress_workers: 4
    \stress_duration_ms: 1000
    \stress_max_failures: 0
    \chaos_faults: interrupt,restart,resume,replay
    \chaos_recovery: resume_then_replay
    \security_capabilities: local_ram,local_disk,event_store
    \security_denials: network,arbitrary_code,source_mutation,direct_terminal_event
;

test "compiles all five canonical schemas deterministically" {
    const a = compile(sample_declaration, sample_config);
    const b = compile(sample_declaration, sample_config);
    try std.testing.expectEqualStrings(a.slice(), b.slice());
    try std.testing.expect(std.mem.indexOf(u8, a.slice(), "pcore.test.unit.v1") != null);
    try std.testing.expect(std.mem.indexOf(u8, a.slice(), "pcore.test.load.v1") != null);
    try std.testing.expect(std.mem.indexOf(u8, a.slice(), "pcore.test.stress.v1") != null);
    try std.testing.expect(std.mem.indexOf(u8, a.slice(), "pcore.test.chaos.v1") != null);
    try std.testing.expect(std.mem.indexOf(u8, a.slice(), "pcore.test.security.v1") != null);
    try std.testing.expect(std.mem.indexOf(u8, a.slice(), "\"persist_payload\":false") == null);
}

test "compiler output keeps runtime as result authority" {
    const output = compile(sample_declaration, sample_config);
    try std.testing.expect(std.mem.indexOf(u8, output.slice(), "\"oracle\":\"runtime-owned\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, output.slice(), "\"terminal_authority\":\"runtime-owned\"") != null);
}
