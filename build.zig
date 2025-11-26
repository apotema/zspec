const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Library module
    const zspec_mod = b.addModule("zspec", .{
        .root_source_file = b.path("src/zspec.zig"),
        .target = target,
        .optimize = optimize,
    });

    // Unit tests for zspec itself
    const lib_unit_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/zspec.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });

    const run_lib_unit_tests = b.addRunArtifact(lib_unit_tests);

    // Example tests using zspec
    const example_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/example_test.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "zspec", .module = zspec_mod },
            },
        }),
        .test_runner = .{ .path = b.path("src/runner.zig"), .mode = .simple },
    });

    const run_example_tests = b.addRunArtifact(example_tests);

    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_lib_unit_tests.step);

    const example_step = b.step("example", "Run example tests");
    example_step.dependOn(&run_example_tests.step);
}
