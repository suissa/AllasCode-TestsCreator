const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const exe = b.addExecutable(.{
        .name = "allascode-tests-creator",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    b.installArtifact(exe);
    const run_cmd = b.addRunArtifact(exe);
    if (b.args) |args| run_cmd.addArgs(args);
    const run_step = b.step("run", "Generate sample contract cases and canonical semantic test bundle");
    run_step.dependOn(&run_cmd.step);

    const tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/generator.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    const test_run = b.addRunArtifact(tests);

    const semantic_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/semantic_compiler.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    const semantic_test_run = b.addRunArtifact(semantic_tests);

    const trajectory_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/trajectory.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    const trajectory_test_run = b.addRunArtifact(trajectory_tests);

    const synthetic_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/synthetic_test.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    const synthetic_test_run = b.addRunArtifact(synthetic_tests);

    const smith_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/smith_fuzz.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    const smith_test_run = b.addRunArtifact(smith_tests);

    const test_step = b.step("test", "Run generator, semantic, trajectory and native Smith fuzzing tests");
    test_step.dependOn(&test_run.step);
    test_step.dependOn(&semantic_test_run.step);
    test_step.dependOn(&trajectory_test_run.step);
    test_step.dependOn(&smith_test_run.step);
    test_step.dependOn(&synthetic_test_run.step);

    const native_fuzz_run = b.addRunArtifact(smith_tests);
    native_fuzz_run.addArgs(&.{"--fuzz=300K"});
    const native_fuzz_step = b.step("test-fuzz", "Run bounded fuzzing using Zig 0.16 std.testing.Smith");
    native_fuzz_step.dependOn(&native_fuzz_run.step);
}
