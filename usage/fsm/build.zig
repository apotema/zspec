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
    const zspec_fsm_mod = zspec_dep.module("zspec-fsm");

    // Get zigfsm dependency
    const zigfsm_dep = b.dependency("zigfsm", .{
        .target = target,
        .optimize = optimize,
    });
    const zigfsm_mod = zigfsm_dep.module("zigfsm");

    // Menu library module
    const menu_mod = b.addModule("menu", .{
        .root_source_file = b.path("src/menu.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "zigfsm", .module = zigfsm_mod },
        },
    });

    // Menu tests
    const menu_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/menu_test.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "menu", .module = menu_mod },
                .{ .name = "zspec", .module = zspec_mod },
                .{ .name = "zspec-fsm", .module = zspec_fsm_mod },
                .{ .name = "zigfsm", .module = zigfsm_mod },
            },
        }),
        .test_runner = .{ .path = zspec_dep.path("src/runner.zig"), .mode = .simple },
    });

    const run_menu_tests = b.addRunArtifact(menu_tests);

    // Test step
    const test_step = b.step("test", "Run menu tests");
    test_step.dependOn(&run_menu_tests.step);
}
