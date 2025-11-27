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

    // Butchery library module
    const butchery_mod = b.addModule("butchery", .{
        .root_source_file = b.path("src/butchery.zig"),
        .target = target,
        .optimize = optimize,
    });

    // Butchery tests
    const butchery_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/butchery_test.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "butchery", .module = butchery_mod },
                .{ .name = "zspec", .module = zspec_mod },
            },
        }),
        .test_runner = .{ .path = zspec_dep.path("src/runner.zig"), .mode = .simple },
    });

    const run_butchery_tests = b.addRunArtifact(butchery_tests);

    // Test step
    const test_step = b.step("test", "Run butchery tests");
    test_step.dependOn(&run_butchery_tests.step);
}
