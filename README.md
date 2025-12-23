# ZSpec

[![CI](https://github.com/apotema/zspec/actions/workflows/ci.yml/badge.svg)](https://github.com/apotema/zspec/actions/workflows/ci.yml)
[![Coverage](https://img.shields.io/endpoint?url=https://gist.githubusercontent.com/apotema/7c6cd8ebc93fc49290cc036271dca4cc/raw/coverage.json)](https://apotema.github.io/zspec/coverage/)

RSpec-like testing framework for Zig.

## Features

- **describe/context** - Organize tests using nested structs
- **before/after** - Run setup/teardown before/after each test
- **beforeAll/afterAll** - Run setup/teardown once per scope
- **let** - Memoized lazy values (computed once per test)
- **expect** - Custom matchers for readable assertions
- **Fluent matchers** - RSpec/Jest-style `expect(x).to().equal(y)` syntax
- **Factory** - FactoryBot-like test data generation
- **Scoped hooks** - Hooks only apply to tests within their struct

## Installation

Add zspec as a dependency in your `build.zig.zon`:

```zig
.dependencies = .{
    .zspec = .{
        .url = "https://github.com/apotema/zspec/archive/refs/heads/main.tar.gz",
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

## Fluent Matchers

ZSpec also provides RSpec/Jest-style fluent matchers with `to()` and `notTo()` syntax:

```zig
const expectFluent = zspec.expectFluent;

// Equality
try expectFluent(@as(i32, 42)).to().equal(42);
try expectFluent(@as([]const u8, "hello")).to().eql("hello");  // deep equality
try expectFluent(@as(i32, 1)).notTo().equal(2);

// Booleans
try expectFluent(true).to().beTrue();
try expectFluent(false).to().beFalse();

// Null checks
try expectFluent(optional).to().beNull();
try expectFluent(optional).notTo().beNull();

// Comparisons
try expectFluent(@as(i32, 10)).to().beGreaterThan(5);
try expectFluent(@as(i32, 5)).to().beLessThan(10);
try expectFluent(@as(i32, 5)).to().beGreaterThanOrEqual(5);
try expectFluent(@as(i32, 5)).to().beLessThanOrEqual(10);
try expectFluent(@as(i32, 5)).to().beBetween(1, 10);

// Strings/Slices
try expectFluent(@as([]const u8, "hello world")).to().contain("world");
try expectFluent(@as([]const u8, "hello")).to().startWith("hel");
try expectFluent(@as([]const u8, "hello")).to().endWith("llo");
try expectFluent(@as([]const u8, "hello")).to().haveLength(5);
try expectFluent(@as([]const u8, "")).to().beEmpty();
```

## Factory (Test Data Generation)

ZSpec includes a FactoryBot-like module for generating test data:

```zig
const Factory = zspec.Factory;

const User = struct {
    id: u32,
    name: []const u8,
    email: []const u8,
    active: bool,
};

// Define a factory with default values
const UserFactory = Factory.define(User, .{
    .id = Factory.sequence(u32),                    // Auto-incrementing
    .name = "John Doe",
    .email = Factory.sequenceFmt("user{d}@example.com"),  // "user1@...", "user2@..."
    .active = true,
});

// Create trait variants
const AdminFactory = UserFactory.trait(.{ .role = "admin" });

pub const UserTests = struct {
    test "tests:before" {
        Factory.resetSequences();  // Reset sequences before each test
    }

    test "creates user with defaults" {
        const user = UserFactory.build(.{});
        try expect.equal(user.id, 1);
        try expect.toBeTrue(std.mem.eql(u8, user.email, "user1@example.com"));
    }

    test "creates user with overrides" {
        const user = UserFactory.build(.{ .name = "Jane Doe" });
        try expect.toBeTrue(std.mem.eql(u8, user.name, "Jane Doe"));
    }

    test "creates pointer with buildPtr" {
        const user_ptr = UserFactory.buildPtr(.{});
        defer std.testing.allocator.destroy(user_ptr);
    }
};
```

### Factory Features

- `Factory.sequence(T)` - Auto-incrementing numeric values
- `Factory.sequenceFmt(fmt)` - Formatted sequence strings
- `Factory.lazy(fn)` / `Factory.lazyAlloc(fn)` - Computed values
- `Factory.assoc(OtherFactory)` - Nested factory associations
- `.trait(overrides)` - Create factory variants with different defaults
- `.build(.{})` / `.buildPtr(.{})` - Create instances
- `.buildWith(alloc, .{})` / `.buildPtrWith(alloc, .{})` - Create with custom allocator
- `Factory.resetSequences()` - Reset all sequence counters

**Note:** When using `sequenceFmt`, use an arena allocator to avoid memory leak reports:

```zig
var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
defer arena.deinit();
const user = UserFactory.buildWith(arena.allocator(), .{});
```

### Loading Factory Definitions from .zon Files

For better separation of concerns, you can load factory definitions from `.zon` files using `Factory.defineFrom()`:

```zig
// factories.zon
.{
    .user = .{
        .id = 0,
        .name = "John Doe",
        .email = "john@example.com",
        .active = true,
    },
    .admin = .{
        .id = 0,
        .name = "Admin User",
        .email = "admin@example.com",
        .active = true,
    },
}
```

```zig
// In your test file
const factory_defs = @import("factories.zon");
const UserFactory = Factory.defineFrom(User, factory_defs.user);
const AdminFactory = Factory.defineFrom(User, factory_defs.admin);

// Use like any other factory
const user = UserFactory.build(.{});
const custom = UserFactory.build(.{ .name = "Jane" });
```

Benefits:
- **Typo detection**: `defineFrom()` validates field names at compile time
- **Separation of concerns**: Test data lives in data files, test logic in test files
- **Reusability**: Share factory definitions across multiple test files
- **Type safety**: Full compile-time type checking via Zig's comptime system

**Note:** `.zon` files contain static comptime data only. For dynamic features like sequences or lazy values, use `define()` directly or apply them via traits.

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

## VS Code Integration

ZSpec includes VS Code configuration for an improved development experience. Open the project in VS Code and you'll get:

### Recommended Extensions

- **[Zig Language](https://marketplace.visualstudio.com/items?itemName=ziglang.vscode-zig)** - Zig language support with ZLS
- **[Test Explorer UI](https://marketplace.visualstudio.com/items?itemName=hbenl.vscode-test-explorer)** - Test Explorer sidebar panel
- **[JUnit Test Adapter](https://marketplace.visualstudio.com/items?itemName=usernamehw.vscode-junit-test-adapter)** - JUnit XML support for Test Explorer

### Test Explorer

To use the Test Explorer sidebar with ZSpec:

1. Install the recommended extensions (Test Explorer UI + JUnit Test Adapter)
2. Run tests with `Ctrl+Shift+B` (default task generates JUnit XML automatically)
3. The Test Explorer will display your test results in the sidebar

### Tasks

Run tests directly from VS Code using the Command Palette (`Ctrl+Shift+P` / `Cmd+Shift+P`):

- `Tasks: Run Task` → `ZSpec: Run All Tests` - Run unit tests
- `Tasks: Run Task` → `ZSpec: Run Example Tests` - Run example test file (tests/example_test.zig)
- `Tasks: Run Task` → `ZSpec: Run All Examples` - Run all example files (examples/*.zig)
- `Tasks: Run Task` → `ZSpec: Run Tests (Verbose)` - Run with verbose output
- `Tasks: Run Task` → `ZSpec: Run Tests (Fail First)` - Stop on first failure
- `Tasks: Run Task` → `ZSpec: Run Tests with Filter` - Run tests matching a pattern

### Keyboard Shortcut

Use `Ctrl+Shift+B` / `Cmd+Shift+B` to run the default test task.

### Debug Configuration

Debug configurations are available for LLDB debugger:

1. Build tests with `zig build test`
2. Use the Debug panel to select "Debug ZSpec Tests"
3. Set breakpoints and start debugging

## Environment Variables

- `TEST_VERBOSE=true` - Show each test result (default: true)
- `TEST_FAIL_FIRST=true` - Stop on first failure
- `TEST_FILTER=pattern` - Only run tests matching pattern
- `TEST_JUNIT_PATH=path` - Generate JUnit XML report at specified path

## CI Integration

ZSpec can generate JUnit XML reports for integration with CI systems like Jenkins, GitHub Actions, GitLab CI, and others.

```bash
# Generate JUnit XML report
TEST_JUNIT_PATH=test-results.xml zig build test
```

### GitHub Actions Example

```yaml
- name: Run tests
  run: TEST_JUNIT_PATH=test-results.xml zig build test

- name: Publish Test Results
  uses: EnricoMi/publish-unit-test-result-action@v2
  if: always()
  with:
    files: test-results.xml
```

### GitLab CI Example

```yaml
test:
  script:
    - TEST_JUNIT_PATH=test-results.xml zig build test
  artifacts:
    reports:
      junit: test-results.xml
```

## Code Coverage

ZSpec supports code coverage using external tools like kcov (Linux).

```bash
# Run tests with coverage
kcov --include-pattern=/src/ coverage ./zig-out/bin/test
```

**[📖 Full Code Coverage Guide](https://github.com/apotema/zspec/wiki/Code-Coverage)**

## License

MIT
