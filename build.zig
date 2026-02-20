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

    // Optional ECS integration module
    const zspec_ecs_mod = b.addModule("zspec-ecs", .{
        .root_source_file = b.path("src/integrations/ecs.zig"),
        .target = target,
        .optimize = optimize,
    });

    // Optional FSM integration module
    const zspec_fsm_mod = b.addModule("zspec-fsm", .{
        .root_source_file = b.path("src/integrations/fsm.zig"),
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

    // Factory union tests (issue #29)
    const factory_union_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/factory_union_test.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "zspec", .module = zspec_mod },
            },
        }),
        .test_runner = .{ .path = b.path("src/runner.zig"), .mode = .simple },
    });

    const run_factory_union_tests = b.addRunArtifact(factory_union_tests);

    // Factory .zon loading tests (issue #31)
    const factory_zon_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/factory_zon_test.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "zspec", .module = zspec_mod },
            },
        }),
        .test_runner = .{ .path = b.path("src/runner.zig"), .mode = .simple },
    });

    const run_factory_zon_tests = b.addRunArtifact(factory_zon_tests);

    // Fixture tests (RFC 001 / issue #38)
    const fixture_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/fixture_test.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "zspec", .module = zspec_mod },
            },
        }),
        .test_runner = .{ .path = b.path("src/runner.zig"), .mode = .simple },
    });

    const run_fixture_tests = b.addRunArtifact(fixture_tests);

    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_lib_unit_tests.step);

    const example_step = b.step("example", "Run example tests");
    example_step.dependOn(&run_example_tests.step);
    example_step.dependOn(&run_factory_union_tests.step);
    example_step.dependOn(&run_factory_zon_tests.step);
    example_step.dependOn(&run_fixture_tests.step);

    // Examples - individual example files
    const example_files = [_]struct { name: []const u8, path: []const u8 }{
        .{ .name = "examples-basic", .path = "examples/basic_test.zig" },
        .{ .name = "examples-hooks", .path = "examples/hooks_test.zig" },
        .{ .name = "examples-let", .path = "examples/let_memoization_test.zig" },
        .{ .name = "examples-matchers", .path = "examples/matchers_test.zig" },
        .{ .name = "examples-factory", .path = "examples/factory_test.zig" },
        .{ .name = "examples-factory-zon", .path = "examples/factory_zon_test.zig" },
        .{ .name = "examples-fixture", .path = "examples/fixture_test.zig" },
        .{ .name = "examples-ecs", .path = "examples/ecs_integration_test.zig" },
        .{ .name = "examples-fsm", .path = "examples/fsm_integration_test.zig" },
    };

    const examples_all_step = b.step("examples", "Run all examples");

    for (example_files) |ex| {
        // Integration examples need the optional modules
        const needs_integrations = std.mem.indexOf(u8, ex.name, "-ecs") != null or
            std.mem.indexOf(u8, ex.name, "-fsm") != null;

        const imports = if (needs_integrations) &[_]std.Build.Module.Import{
            .{ .name = "zspec", .module = zspec_mod },
            .{ .name = "zspec-ecs", .module = zspec_ecs_mod },
            .{ .name = "zspec-fsm", .module = zspec_fsm_mod },
        } else &[_]std.Build.Module.Import{
            .{ .name = "zspec", .module = zspec_mod },
        };

        const ex_test = b.addTest(.{
            .root_module = b.createModule(.{
                .root_source_file = b.path(ex.path),
                .target = target,
                .optimize = optimize,
                .imports = imports,
            }),
            .test_runner = .{ .path = b.path("src/runner.zig"), .mode = .simple },
        });

        const run_ex = b.addRunArtifact(ex_test);
        const ex_step = b.step(ex.name, b.fmt("Run {s}", .{ex.path}));
        ex_step.dependOn(&run_ex.step);
        examples_all_step.dependOn(&run_ex.step);
    }
}
