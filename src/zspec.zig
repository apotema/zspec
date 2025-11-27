//! ZSpec - RSpec-like testing framework for Zig
//!
//! Provides:
//! - describe/context blocks via nested structs
//! - before/after hooks (per-test)
//! - beforeAll/afterAll hooks (per-scope)
//! - let (memoized lazy values)
//! - Custom matchers and assertions
//! - Factory (FactoryBot-like test data generation)

const std = @import("std");
const builtin = @import("builtin");

// Re-export Factory module
pub const Factory = @import("factory.zig");

// Re-export fluent matchers module
pub const matchers = @import("matchers.zig");
/// Fluent expect function: try expectFluent(value).to().equal(expected)
pub const expectFluent = matchers.expect;

/// Memoized lazy value that is computed once per test and cached.
/// Similar to RSpec's `let`.
pub fn Let(comptime T: type, comptime init_fn: fn () T) type {
    return struct {
        var cached_value: ?T = null;
        var initialized: bool = false;

        pub fn get() T {
            if (!initialized) {
                cached_value = init_fn();
                initialized = true;
            }
            return cached_value.?;
        }

        pub fn reset() void {
            cached_value = null;
            initialized = false;
        }
    };
}

/// Memoized lazy value with allocator support for heap allocations.
pub fn LetAlloc(comptime T: type, comptime init_fn: fn (std.mem.Allocator) T) type {
    return struct {
        var cached_value: ?T = null;
        var initialized: bool = false;

        pub fn get(alloc: std.mem.Allocator) T {
            if (!initialized) {
                cached_value = init_fn(alloc);
                initialized = true;
            }
            return cached_value.?;
        }

        pub fn reset() void {
            cached_value = null;
            initialized = false;
        }
    };
}

/// Custom expectation/matcher system
pub const expect = struct {
    pub fn equal(actual: anytype, expected: @TypeOf(actual)) !void {
        if (actual != expected) {
            std.debug.print("\n  Expected: {any}\n  Actual:   {any}\n", .{ expected, actual });
            return error.ExpectationFailed;
        }
    }

    pub fn notEqual(actual: anytype, expected: @TypeOf(actual)) !void {
        if (actual == expected) {
            std.debug.print("\n  Expected {any} to not equal {any}\n", .{ actual, expected });
            return error.ExpectationFailed;
        }
    }

    pub fn toBeTrue(actual: bool) !void {
        if (!actual) {
            std.debug.print("\n  Expected true, got false\n", .{});
            return error.ExpectationFailed;
        }
    }

    pub fn toBeFalse(actual: bool) !void {
        if (actual) {
            std.debug.print("\n  Expected false, got true\n", .{});
            return error.ExpectationFailed;
        }
    }

    pub fn toBeNull(actual: anytype) !void {
        if (actual != null) {
            std.debug.print("\n  Expected null, got {any}\n", .{actual});
            return error.ExpectationFailed;
        }
    }

    pub fn notToBeNull(actual: anytype) !void {
        if (actual == null) {
            std.debug.print("\n  Expected non-null value, got null\n", .{});
            return error.ExpectationFailed;
        }
    }

    pub fn toBeGreaterThan(actual: anytype, expected: @TypeOf(actual)) !void {
        if (actual <= expected) {
            std.debug.print("\n  Expected {any} > {any}\n", .{ actual, expected });
            return error.ExpectationFailed;
        }
    }

    pub fn toBeLessThan(actual: anytype, expected: @TypeOf(actual)) !void {
        if (actual >= expected) {
            std.debug.print("\n  Expected {any} < {any}\n", .{ actual, expected });
            return error.ExpectationFailed;
        }
    }

    pub fn toContain(haystack: []const u8, needle: []const u8) !void {
        if (std.mem.indexOf(u8, haystack, needle) == null) {
            std.debug.print("\n  Expected \"{s}\" to contain \"{s}\"\n", .{ haystack, needle });
            return error.ExpectationFailed;
        }
    }

    pub fn toHaveLength(slice: anytype, expected_len: usize) !void {
        const actual_len = slice.len;
        if (actual_len != expected_len) {
            std.debug.print("\n  Expected length {d}, got {d}\n", .{ expected_len, actual_len });
            return error.ExpectationFailed;
        }
    }

    pub fn toBeEmpty(slice: anytype) !void {
        if (slice.len != 0) {
            std.debug.print("\n  Expected empty, got length {d}\n", .{slice.len});
            return error.ExpectationFailed;
        }
    }

    pub fn notToBeEmpty(slice: anytype) !void {
        if (slice.len == 0) {
            std.debug.print("\n  Expected non-empty slice\n", .{});
            return error.ExpectationFailed;
        }
    }
};

/// Describes a test suite. Use with nested structs for organization.
/// This is mainly for documentation - the actual structure comes from nested pub const structs.
pub fn describe(comptime name: []const u8, comptime T: type) type {
    _ = name; // Name is embedded in the struct for the test runner to discover
    return T;
}

/// Alias for describe - used for sub-contexts
pub const context = describe;

/// Helper to run all tests in a spec struct
pub fn runAll(comptime T: type) void {
    _ = std.testing.refAllDeclsRecursive(T);
}

// Re-export testing allocator for convenience
pub const allocator = std.testing.allocator;

test "Let memoization" {
    var call_count: usize = 0;

    const TestLet = struct {
        var counter: *usize = undefined;

        fn init() i32 {
            counter.* += 1;
            return 42;
        }
    };
    TestLet.counter = &call_count;

    const value = Let(i32, TestLet.init);

    // First call should initialize
    try std.testing.expectEqual(42, value.get());
    try std.testing.expectEqual(1, call_count);

    // Second call should return cached value
    try std.testing.expectEqual(42, value.get());
    try std.testing.expectEqual(1, call_count);

    // Reset and call again
    value.reset();
    try std.testing.expectEqual(42, value.get());
    try std.testing.expectEqual(2, call_count);
}

test "expect.equal" {
    try expect.equal(1, 1);
    try expect.equal("hello", "hello");
}

test "expect.toBeTrue" {
    try expect.toBeTrue(true);
    try expect.toBeTrue(5 > 3);
}

test "expect.toBeFalse" {
    try expect.toBeFalse(false);
    try expect.toBeFalse(3 > 5);
}

test "expect.toContain" {
    try expect.toContain("hello world", "world");
    try expect.toContain("hello world", "hello");
}

test "expect.toHaveLength" {
    const arr = [_]i32{ 1, 2, 3 };
    try expect.toHaveLength(&arr, 3);
    try expect.toHaveLength("hello", 5);
}

// Include tests from submodules
test {
    _ = @import("factory.zig");
    _ = @import("matchers.zig");
}
