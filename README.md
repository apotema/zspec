# ZSpec

RSpec-like testing framework for Zig.

## Features

- **describe/context** - Organize tests using nested structs
- **before/after** - Run setup/teardown before/after each test
- **beforeAll/afterAll** - Run setup/teardown once per scope
- **let** - Memoized lazy values (computed once per test)
- **expect** - Custom matchers for readable assertions
- **Scoped hooks** - Hooks only apply to tests within their struct

## Installation

Add zspec as a dependency in your `build.zig.zon`:

```zig
.dependencies = .{
    .zspec = .{
        .url = "https://github.com/yourusername/zspec/archive/refs/heads/main.tar.gz",
        .hash = "...",
    },
},
```

In your `build.zig`:

```zig
const zspec = b.dependency("zspec", .{
    .target = target,
    .optimize = optimize,
});

const tests = b.addTest(.{
    .root_module = b.createModule(.{
        .root_source_file = b.path("tests/my_test.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "zspec", .module = zspec.module("zspec") },
        },
    }),
    .test_runner = .{ .path = zspec.path("src/runner.zig"), .mode = .simple },
});
```

## Usage

```zig
const std = @import("std");
const zspec = @import("zspec");
const expect = zspec.expect;

test {
    zspec.runAll(@This());
}

// Top-level hooks run for all tests
test "tests:beforeAll" {
    std.debug.print("Starting tests...\n", .{});
}

test "tests:afterAll" {
    std.debug.print("Done!\n", .{});
}

pub const Calculator = struct {
    var value: i32 = undefined;

    // Scoped hooks - only run for tests in this struct
    test "tests:before" {
        value = 0;
    }

    test "tests:after" {
        // cleanup
    }

    test "adds numbers" {
        value += 5;
        try expect.equal(value, 5);
    }

    test "subtracts numbers" {
        value -= 3;
        try expect.equal(value, -3);
    }
};

// Nested contexts
pub const StringUtils = struct {
    pub const Uppercase = struct {
        test "converts to uppercase" {
            try expect.toBeTrue(true);
        }
    };
};
```

## Hooks

| Hook | Suffix | When it runs |
|------|--------|--------------|
| `beforeAll` | `tests:beforeAll` | Once before first test in scope |
| `afterAll` | `tests:afterAll` | Once after all tests in scope |
| `before` | `tests:before` | Before each test in scope |
| `after` | `tests:after` | After each test in scope |

Parent hooks also apply to nested scopes.

## Let (Memoized Values)

```zig
const zspec = @import("zspec");

pub const MyTests = struct {
    fn createUser() User {
        return User.init("test@example.com");
    }

    const user = zspec.Let(User, createUser);

    test "tests:after" {
        user.reset(); // Reset for next test
    }

    test "user has email" {
        try zspec.expect.equal(user.get().email, "test@example.com");
    }
};
```

## Matchers

```zig
const expect = zspec.expect;

try expect.equal(1, 1);
try expect.notEqual(1, 2);
try expect.toBeTrue(condition);
try expect.toBeFalse(condition);
try expect.toBeNull(optional);
try expect.notToBeNull(optional);
try expect.toBeGreaterThan(10, 5);
try expect.toBeLessThan(5, 10);
try expect.toContain("hello world", "world");
try expect.toHaveLength(slice, 3);
try expect.toBeEmpty(slice);
try expect.notToBeEmpty(slice);
```

## Optional Integrations

### ECS Integration (zig-ecs)

ZSpec provides an optional `zspec-ecs` module for testing Entity Component Systems with [zig-ecs](https://github.com/prime31/zig-ecs).

```zig
const ECS = @import("zspec-ecs");

test "creates entities with components" {
    const registry = ECS.createRegistry(ecs.Registry);
    defer ECS.destroyRegistry(registry);

    const entity = ECS.createEntity(registry, .{
        .position = PositionFactory.build(.{}),
        .health = HealthFactory.build(.{}),
    });
}
```

**[📖 Full ECS Integration Guide](https://github.com/apotema/zspec/wiki/ECS-Integration)** | [Examples](examples/ecs_integration_test.zig) | [Usage Project](usage/ecs/)

### FSM Integration (zigfsm)

ZSpec provides an optional `zspec-fsm` module for testing Finite State Machines with [zigfsm](https://github.com/cryptocode/zigfsm).

```zig
const FSM = @import("zspec-fsm");

test "state transitions" {
    var fsm = MyFSM.init();
    defer fsm.deinit();

    // Bulk transition setup
    try FSM.addTransitions(MyFSM, &fsm, &.{
        .{ .event = .start, .from = .idle, .to = .running },
        .{ .event = .stop, .from = .running, .to = .stopped },
    });

    // Test event sequence
    try FSM.applyEventsAndVerify(MyFSM, &fsm, &.{ .start, .stop }, .stopped);
}
```

**[📖 Full FSM Integration Guide](https://github.com/apotema/zspec/wiki/FSM-Integration)** | [Examples](examples/fsm_integration_test.zig) | [Usage Project](usage/fsm/)

## Running Tests

```bash
zig build test      # Run zspec's own tests
zig build example   # Run example tests
```

## Environment Variables

- `TEST_VERBOSE=true` - Show each test result (default: true)
- `TEST_FAIL_FIRST=true` - Stop on first failure
- `TEST_FILTER=pattern` - Only run tests matching pattern

## License

MIT
