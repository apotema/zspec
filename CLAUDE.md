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
