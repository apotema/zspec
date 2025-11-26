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
    const zspec_ecs_mod = zspec_dep.module("zspec-ecs");

    // Get zig-ecs dependency
    const ecs_dep = b.dependency("ecs", .{
        .target = target,
        .optimize = optimize,
    });
    const ecs_mod = ecs_dep.module("zig-ecs");

    // Game library module
    const game_mod = b.addModule("game", .{
        .root_source_file = b.path("src/game.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "zig-ecs", .module = ecs_mod },
        },
    });

    // Game tests
    const game_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/game_test.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "game", .module = game_mod },
                .{ .name = "zspec", .module = zspec_mod },
                .{ .name = "zspec-ecs", .module = zspec_ecs_mod },
                .{ .name = "zig-ecs", .module = ecs_mod },
            },
        }),
        .test_runner = .{ .path = zspec_dep.path("src/runner.zig"), .mode = .simple },
    });

    const run_game_tests = b.addRunArtifact(game_tests);

    // Test step
    const test_step = b.step("test", "Run game tests");
    test_step.dependOn(&run_game_tests.step);
}
