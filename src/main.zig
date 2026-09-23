const std = @import("std");
const model = @import("model.zig");
const generator = @import("generator.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const params = [_]model.ParameterSpec{
        .{ .name = "name", .constraints = .{ .string = .{ .min_len = 1, .max_len = 80 } } },
        .{ .name = "age", .constraints = .{ .integer = .{ .min = 18, .max = 120 } } },
        .{ .name = "active", .constraints = .{ .boolean = {} } },
    };
    var plan = try generator.generate(allocator, .{ .name = "CreateUser", .parameters = &params }, 42);
    defer plan.deinit(allocator);

    var buffer: [4096]u8 = undefined;
    var out = std.fs.File.stdout().writer(&buffer);
    try out.interface.print("function={s} seed={d} cases={d} ephemeral={} persist_payload={} persist_events={}\n", .{
        plan.function_name, plan.seed, plan.cases.len, plan.policy.ephemeral, plan.policy.persist_payload, plan.policy.persist_events,
    });
    for (plan.cases) |case| try out.interface.print("{s} [{s}]\n", .{case.name, @tagName(case.kind)});
    try out.interface.flush();
}
