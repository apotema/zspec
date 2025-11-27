const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Get zspec dependency (from parent directory)
    const zspec_dep = b.dependency("zspec", .{
        .target = target,
        .optimize = optimize,
    });
    const zspec_mod = zspec_dep.module("zspec");

    // Calculator module (example code to test)
    const calc_mod = b.addModule("calculator", .{
        .root_source_file = b.path("src/calculator.zig"),
        .target = target,
        .optimize = optimize,
    });

    // Calculator tests using fluent matchers
    const calc_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/calculator_test.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "calculator", .module = calc_mod },
                .{ .name = "zspec", .module = zspec_mod },
            },
        }),
        .test_runner = .{ .path = zspec_dep.path("src/runner.zig"), .mode = .simple },
    });

    const run_calc_tests = b.addRunArtifact(calc_tests);

    // Test step
    const test_step = b.step("test", "Run calculator tests");
    test_step.dependOn(&run_calc_tests.step);
}
