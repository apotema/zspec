# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build Commands

```bash
zig build test      # Run zspec's own unit tests
zig build example   # Run example tests (tests/example_test.zig)
zig build examples  # Run all example files (examples/*.zig)
```

## Environment Variables for Test Runner

- `TEST_VERBOSE=true` - Show each test result (default: true)
- `TEST_FAIL_FIRST=true` - Stop on first failure
- `TEST_FILTER=pattern` - Only run tests matching pattern

## Architecture

ZSpec is an RSpec-like testing framework for Zig with these main components:

**src/zspec.zig** - The library module providing:
- `Let(T, init_fn)` / `LetAlloc(T, init_fn)` - Memoized lazy values (computed once per test, reset manually)
- `expect` - Assertion matchers (`equal`, `toBeTrue`, `toContain`, etc.)
- `runAll(T)` - Entry point that uses `std.testing.refAllDeclsRecursive` to discover tests
- `Factory` - Re-exported factory module for test data generation

**src/factory.zig** - FactoryBot-like test data generation:
- `Factory.define(T, defaults)` - Define a factory with default values
- `Factory.sequence(T)` - Auto-incrementing numeric sequences
- `Factory.sequenceFmt(fmt)` - Formatted sequence strings (e.g., "user{d}@example.com")
- `Factory.lazy(fn)` / `Factory.lazyAlloc(fn)` - Computed values
- `Factory.assoc(OtherFactory)` - Nested factory associations
- `.trait(overrides)` - Create factory variants with different defaults
- `.build(.{})` / `.buildPtr(.{})` - Create instances (uses std.testing.allocator)
- `.buildWith(alloc, .{})` / `.buildPtrWith(alloc, .{})` - Create with custom allocator

**src/integrations/ecs.zig** - Optional ECS integration module for zig-ecs (https://github.com/prime31/zig-ecs):
- Exposed as separate "zspec-ecs" module that users opt into
- `ECS.createRegistry(T)` / `ECS.destroyRegistry(reg)` - Registry setup/teardown
- `ECS.createEntity(reg, .{ .comp = ... })` - Create entity with components
- `ECS.createEntities(reg, count, .{})` - Batch create entities
- `ECS.ComponentFactory(T, Factory)` - Component-specific factory wrapper
- Used in before/after hooks for registry management
- Combines with Factory for component data generation
- Import with: `const ECS = @import("zspec-ecs");`
- See usage/ecs/ for complete example project

**src/integrations/fsm.zig** - Optional FSM integration module for zigfsm (https://github.com/cryptocode/zigfsm):
- Exposed as separate "zspec-fsm" module that users opt into
- `FSM.addTransitions(FSMType, fsm, transitions)` - Bulk transition setup
- `FSM.applyEventsAndVerify(FSMType, fsm, events, expected_state)` - Event sequence testing
- `FSM.expectValidNextStates(FSMType, fsm, states)` - State validation helpers
- `FSM.FSMBuilder(FSMType)` - Builder pattern for fluent FSM configuration
- Used in before/after hooks for FSM initialization/cleanup
- Combines with Factory for test state generation
- Import with: `const FSM = @import("zspec-fsm");`
- See usage/fsm/ for complete example project

**src/runner.zig** - Custom test runner that processes hooks and provides output:
- Hooks are identified by test name suffixes: `tests:beforeAll`, `tests:afterAll`, `tests:before`, `tests:after`
- Scoped hooks: hooks only apply to tests within their containing struct (determined by comparing name prefixes)
- Tracks slowest tests and supports colorized output

## Test Organization Pattern

Tests use nested `pub const` structs to create describe/context blocks. Each struct can have its own hooks:

```zig
pub const Calculator = struct {
    var value: i32 = undefined;

    test "tests:before" { value = 0; }  // runs before each test in this struct
    test "tests:after" { }               // runs after each test in this struct
    test "tests:beforeAll" { }           // runs once before first test in struct
    test "tests:afterAll" { }            // runs once after all tests in struct

    test "adds numbers" {
        value += 5;
        try expect.equal(value, 5);
    }
};
```

Parent hooks apply to nested structs. The hook scope matching logic is in `hookAppliesToTest()` in runner.zig.

## Factory Pattern

```zig
const UserFactory = Factory.define(User, .{
    .id = Factory.sequence(u32),
    .email = Factory.sequenceFmt("user{d}@example.com"),
    .name = "John Doe",
    .company = null,  // optional pointers default to null
});

const AdminFactory = UserFactory.trait(.{ .role = "admin" });

// Usage - use arena allocator to avoid leaks from sequenceFmt
const user = UserFactory.buildWith(arena_alloc, .{});
const admin = AdminFactory.buildWith(arena_alloc, .{ .name = "Custom Name" });
```

## ECS Integration Pattern (zig-ecs)

NOTE: ECS integration is an optional separate module. Import with:
```zig
const zspec = @import("zspec");
const ecs = @import("zig-ecs");
const ECS = @import("zspec-ecs");  // Optional module

// Define component factories
const PositionFactory = Factory.define(Position, .{
    .x = 0.0,
    .y = 0.0,
});

const HealthFactory = Factory.define(Health, .{
    .current = 100,
    .max = 100,
});

pub const GameTests = struct {
    var registry: *ecs.Registry = undefined;

    test "tests:before" {
        Factory.resetSequences();
        registry = ECS.createRegistry(ecs.Registry);
    }

    test "tests:after" {
        ECS.destroyRegistry(registry);
    }

    test "creates entities" {
        // Single entity with components
        const player = ECS.createEntity(registry, .{
            .position = PositionFactory.build(.{ .x = 10.0 }),
            .health = HealthFactory.build(.{}),
        });

        // Batch create
        const enemies = ECS.createEntities(registry, 5, .{
            .position = PositionFactory.build(.{}),
        });
        defer std.testing.allocator.free(enemies);
    }
};

// Alternative: Using Let for memoized registry
pub const LetBasedTests = struct {
    fn createRegistry() *ecs.Registry {
        return ECS.createRegistry(ecs.Registry);
    }

    const registry = zspec.Let(*ecs.Registry, createRegistry);

    test "tests:after" {
        ECS.destroyRegistry(registry.get());
        registry.reset();
    }

    test "my test" {
        const entity = ECS.createEntity(registry.get(), .{
            .position = PositionFactory.build(.{}),
        });
    }
};
```

## FSM Integration Pattern (zigfsm)

NOTE: FSM integration is an optional separate module. Import with:
```zig
const zspec = @import("zspec");
const zigfsm = @import("zigfsm");
const FSM = @import("zspec-fsm");  // Optional module

const State = enum { idle, running, stopped };
const Event = enum { start, stop };

pub const FSMTests = struct {
    const MyFSM = zigfsm.StateMachine(State, Event, .idle);
    var fsm: MyFSM = undefined;

    test "tests:before" {
        Factory.resetSequences();
        fsm = MyFSM.init();
        // Bulk transition setup
        try FSM.addTransitions(MyFSM, &fsm, &.{
            .{ .event = .start, .from = .idle, .to = .running },
            .{ .event = .stop, .from = .running, .to = .stopped },
        });
    }

    test "tests:after" {
        fsm.deinit();
    }

    test "state transitions" {
        try fsm.do(.start);
        try zspec.expect.toBeTrue(fsm.isCurrently(.running));
    }

    test "event sequence" {
        // Apply multiple events and verify final state
        try FSM.applyEventsAndVerify(MyFSM, &fsm, &.{
            .start,
            .stop,
        }, .stopped);
    }
};

// Alternative: Using FSM Builder pattern
pub const BuilderTests = struct {
    test "build FSM with builder" {
        const Builder = FSM.FSMBuilder(MyFSM);

        var builder = Builder.init();
        _ = try builder.withEvent(.start, .idle, .running);
        _ = try builder.withEvent(.stop, .running, .stopped);

        var fsm = builder.build();
        defer fsm.deinit();

        try fsm.do(.start);
        try zspec.expect.toBeTrue(fsm.isCurrently(.running));
    }
};
```
