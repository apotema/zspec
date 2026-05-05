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

// Re-export Fixture module
pub const Fixture = @import("fixture.zig");

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

/// Comparison helper for `expect.equal` / `expect.notEqual`. Dispatches
/// on `@typeInfo` so types that don't support `==` (slices, error unions)
/// still compare correctly:
///
///   - Slices compare element-wise via `std.mem.eql` so `[]const u8`
///     equality "just works" without forcing callers into
///     `std.testing.expectEqualStrings`.
///   - Error unions compare by resolving both sides: same error → equal,
///     same payload (recursively) → equal, mismatched outcomes → not equal.
///   - Everything else falls through to plain `==`, preserving the
///     existing behavior for primitives, enums, simple structs, etc.
fn valuesEqual(actual: anytype, expected: @TypeOf(actual)) bool {
    const T = @TypeOf(actual);
    switch (@typeInfo(T)) {
        .pointer => |p| {
            if (p.size == .slice) return std.mem.eql(p.child, actual, expected);
            return actual == expected;
        },
        .error_union => {
            // Resolve both sides into either an error or a payload, then
            // compare the matching variants. Using `if (x) |v| ... else |e| ...`
            // (rather than `x catch |e| e`) is the only way to extract a
            // bare error-set value from an error union without dragging
            // the union back into the result type.
            if (actual) |a_val| {
                const e_val = expected catch return false;
                return valuesEqual(a_val, e_val);
            } else |a_err| {
                if (expected) |_| {
                    return false;
                } else |e_err| {
                    return a_err == e_err;
                }
            }
        },
        else => return actual == expected,
    }
}

/// Custom expectation/matcher system
pub const expect = struct {
    pub fn equal(actual: anytype, expected: @TypeOf(actual)) !void {
        if (!valuesEqual(actual, expected)) {
            std.debug.print("\n  Expected: {any}\n  Actual:   {any}\n", .{ expected, actual });
            return error.ExpectationFailed;
        }
    }

    pub fn notEqual(actual: anytype, expected: @TypeOf(actual)) !void {
        if (valuesEqual(actual, expected)) {
            std.debug.print("\n  Expected {any} to not equal {any}\n", .{ actual, expected });
            return error.ExpectationFailed;
        }
    }

    /// Assert that an error-union value resolved to a specific error.
    /// Mirrors `std.testing.expectError` with zspec's stderr formatting.
    /// Use this instead of `expect.equal(result, error.Foo)` — `equal`
    /// can compare error unions, but `toReturnError` reads better at the
    /// call site for "this should have errored" assertions.
    pub fn toReturnError(actual: anytype, expected: anyerror) !void {
        const T = @TypeOf(actual);
        if (@typeInfo(T) != .error_union)
            @compileError("expect.toReturnError requires an error-union value, got " ++ @typeName(T));

        if (actual) |_| {
            std.debug.print("\n  Expected error.{s}, but got a value\n", .{@errorName(expected)});
            return error.ExpectationFailed;
        } else |actual_err| {
            if (actual_err != expected) {
                std.debug.print("\n  Expected error.{s}, got error.{s}\n", .{ @errorName(expected), @errorName(actual_err) });
                return error.ExpectationFailed;
            }
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

test "expect.toHaveLength" {
    const arr = [_]i32{ 1, 2, 3 };
    try expect.toHaveLength(&arr, 3);
}

// ── expect.equal / notEqual / toReturnError on slices and error unions ──
//
// Pre-#40 these failed at compile time with
// "operator != not allowed for type '[]const u8'" / "...error union".
// The tests below pin the smart-dispatch in valuesEqual + the new
// toReturnError matcher.

test "expect.equal: slice of u8 (string) — equal contents" {
    try expect.equal(@as([]const u8, "hello"), "hello");
}

test "expect.equal: slice of u8 — same length, different bytes" {
    try std.testing.expectError(
        error.ExpectationFailed,
        expect.equal(@as([]const u8, "hello"), "world"),
    );
}

test "expect.equal: slice of u8 — different length" {
    try std.testing.expectError(
        error.ExpectationFailed,
        expect.equal(@as([]const u8, "hi"), "hello"),
    );
}

test "expect.equal: slice of i32" {
    const a = [_]i32{ 1, 2, 3 };
    const b = [_]i32{ 1, 2, 3 };
    try expect.equal(@as([]const i32, &a), @as([]const i32, &b));
}

test "expect.notEqual: slice of u8 — different contents" {
    try expect.notEqual(@as([]const u8, "hello"), "world");
}

test "expect.notEqual: slice of u8 — equal contents fails" {
    try std.testing.expectError(
        error.ExpectationFailed,
        expect.notEqual(@as([]const u8, "hello"), "hello"),
    );
}

test "expect.equal: error union — both same error" {
    const Result = error{Foo}!u32;
    const a: Result = error.Foo;
    const b: Result = error.Foo;
    try expect.equal(a, b);
}

test "expect.equal: error union — both same payload" {
    const Result = error{Foo}!u32;
    const a: Result = 42;
    const b: Result = 42;
    try expect.equal(a, b);
}

test "expect.equal: error union — error vs payload fails" {
    const Result = error{Foo}!u32;
    const a: Result = error.Foo;
    const b: Result = 42;
    try std.testing.expectError(error.ExpectationFailed, expect.equal(a, b));
}

test "expect.equal: error union — different errors fail" {
    const Result = error{ Foo, Bar }!u32;
    const a: Result = error.Foo;
    const b: Result = error.Bar;
    try std.testing.expectError(error.ExpectationFailed, expect.equal(a, b));
}

test "expect.equal: error union with slice payload — recurses" {
    const Result = error{Foo}![]const u8;
    const a: Result = "hello";
    const b: Result = "hello";
    try expect.equal(a, b);
}

test "expect.toReturnError: matches expected error" {
    const Result = error{Foo}!u32;
    const a: Result = error.Foo;
    try expect.toReturnError(a, error.Foo);
}

test "expect.toReturnError: mismatch fails" {
    const Result = error{ Foo, Bar }!u32;
    const a: Result = error.Foo;
    try std.testing.expectError(
        error.ExpectationFailed,
        expect.toReturnError(a, error.Bar),
    );
}

test "expect.toReturnError: payload-instead-of-error fails" {
    const Result = error{Foo}!u32;
    const a: Result = 42;
    try std.testing.expectError(
        error.ExpectationFailed,
        expect.toReturnError(a, error.Foo),
    );
}

// Sanity check: the existing non-slice non-error path still works.
test "expect.equal: int (regression check for the dispatch fall-through)" {
    try expect.equal(@as(u32, 42), 42);
    try std.testing.expectError(error.ExpectationFailed, expect.equal(@as(u32, 1), @as(u32, 2)));
}

// Include tests from submodules
test {
    _ = @import("factory.zig");
    _ = @import("fixture.zig");
    _ = @import("matchers.zig");
}
