//! ZSpec Fluent Matchers
//!
//! Provides RSpec/Jest-style fluent assertions:
//!   try expect(actual).to().equal(expected);
//!   try expect(condition).to().beTrue();
//!   try expect(value).notTo().beNull();
//!   try expect(slice).to().contain("needle");
//!
//! Supports negation via .notTo():
//!   try expect(x).notTo().equal(y);
//!   try expect(opt).notTo().beNull();
//!
//! Available Matchers:
//! - Equality: equal(), eql() (deep equality)
//! - Boolean: beTrue(), beFalse()
//! - Null: beNull()
//! - Comparison: beGreaterThan(), beLessThan(), beGreaterThanOrEqual(),
//!               beLessThanOrEqual(), beBetween()
//! - String/Slice: contain(), startWith(), endWith(), haveLength(), beEmpty()
//! - Type: beOfType()

const std = @import("std");

/// Creates a fluent matcher for the given value.
/// Usage: try expect(value).to().equal(expected);
pub fn expect(value: anytype) Matcher(@TypeOf(value)) {
    return Matcher(@TypeOf(value)).init(value);
}

/// Fluent matcher type that provides chainable assertions.
pub fn Matcher(comptime T: type) type {
    return struct {
        value: T,

        const Self = @This();

        pub fn init(value: T) Self {
            return .{ .value = value };
        }

        /// Bridge to matchers namespace (positive assertion).
        /// Usage: expect(x).to().equal(y)
        pub fn to(self: Self) ToMatcher(T, false) {
            return ToMatcher(T, false).init(self.value);
        }

        /// Bridge to matchers namespace (negated assertion).
        /// Usage: expect(x).notTo().equal(y)
        pub fn notTo(self: Self) ToMatcher(T, true) {
            return ToMatcher(T, true).init(self.value);
        }
    };
}

/// The actual matcher implementations.
fn ToMatcher(comptime T: type, comptime negated: bool) type {
    return struct {
        value: T,

        const Self = @This();

        pub fn init(value: T) Self {
            return .{ .value = value };
        }

        // =========================================================
        // Equality Matchers
        // =========================================================

        /// Asserts that actual equals expected (pointer equality for slices).
        pub fn equal(self: Self, expected: T) !void {
            const matches = self.value == expected;
            if (shouldFail(negated, matches)) {
                if (negated) {
                    std.debug.print("\n  Expected {any} to NOT equal {any}\n", .{ self.value, expected });
                } else {
                    std.debug.print("\n  Expected: {any}\n  Actual:   {any}\n", .{ expected, self.value });
                }
                return error.ExpectationFailed;
            }
        }

        /// Asserts deep equality for slices/arrays/structs.
        pub fn eql(self: Self, expected: T) !void {
            const matches = std.meta.eql(self.value, expected);
            if (shouldFail(negated, matches)) {
                if (negated) {
                    std.debug.print("\n  Expected values to NOT be deeply equal\n", .{});
                } else {
                    std.debug.print("\n  Expected deep equality\n  Expected: {any}\n  Actual:   {any}\n", .{ expected, self.value });
                }
                return error.ExpectationFailed;
            }
        }

        // =========================================================
        // Boolean Matchers
        // =========================================================

        /// Asserts that value is true.
        pub fn beTrue(self: Self) !void {
            const is_bool = T == bool;
            if (!is_bool) {
                @compileError("beTrue() requires a bool value");
            }
            const matches = self.value == true;
            if (shouldFail(negated, matches)) {
                if (negated) {
                    std.debug.print("\n  Expected false, got true\n", .{});
                } else {
                    std.debug.print("\n  Expected true, got false\n", .{});
                }
                return error.ExpectationFailed;
            }
        }

        /// Asserts that value is false.
        pub fn beFalse(self: Self) !void {
            const is_bool = T == bool;
            if (!is_bool) {
                @compileError("beFalse() requires a bool value");
            }
            const matches = self.value == false;
            if (shouldFail(negated, matches)) {
                if (negated) {
                    std.debug.print("\n  Expected true, got false\n", .{});
                } else {
                    std.debug.print("\n  Expected false, got true\n", .{});
                }
                return error.ExpectationFailed;
            }
        }

        // =========================================================
        // Null/Optional Matchers
        // =========================================================

        /// Asserts that value is null.
        pub fn beNull(self: Self) !void {
            const matches = self.value == null;
            if (shouldFail(negated, matches)) {
                if (negated) {
                    std.debug.print("\n  Expected non-null value, got null\n", .{});
                } else {
                    std.debug.print("\n  Expected null, got {any}\n", .{self.value});
                }
                return error.ExpectationFailed;
            }
        }

        // =========================================================
        // Comparison Matchers
        // =========================================================

        /// Asserts that actual > expected.
        pub fn beGreaterThan(self: Self, expected: T) !void {
            const matches = self.value > expected;
            if (shouldFail(negated, matches)) {
                if (negated) {
                    std.debug.print("\n  Expected {any} to NOT be greater than {any}\n", .{ self.value, expected });
                } else {
                    std.debug.print("\n  Expected {any} > {any}\n", .{ self.value, expected });
                }
                return error.ExpectationFailed;
            }
        }

        /// Asserts that actual >= expected.
        pub fn beGreaterThanOrEqual(self: Self, expected: T) !void {
            const matches = self.value >= expected;
            if (shouldFail(negated, matches)) {
                if (negated) {
                    std.debug.print("\n  Expected {any} to NOT be >= {any}\n", .{ self.value, expected });
                } else {
                    std.debug.print("\n  Expected {any} >= {any}\n", .{ self.value, expected });
                }
                return error.ExpectationFailed;
            }
        }

        /// Asserts that actual < expected.
        pub fn beLessThan(self: Self, expected: T) !void {
            const matches = self.value < expected;
            if (shouldFail(negated, matches)) {
                if (negated) {
                    std.debug.print("\n  Expected {any} to NOT be less than {any}\n", .{ self.value, expected });
                } else {
                    std.debug.print("\n  Expected {any} < {any}\n", .{ self.value, expected });
                }
                return error.ExpectationFailed;
            }
        }

        /// Asserts that actual <= expected.
        pub fn beLessThanOrEqual(self: Self, expected: T) !void {
            const matches = self.value <= expected;
            if (shouldFail(negated, matches)) {
                if (negated) {
                    std.debug.print("\n  Expected {any} to NOT be <= {any}\n", .{ self.value, expected });
                } else {
                    std.debug.print("\n  Expected {any} <= {any}\n", .{ self.value, expected });
                }
                return error.ExpectationFailed;
            }
        }

        /// Asserts that actual is between min and max (inclusive).
        pub fn beBetween(self: Self, min: T, max: T) !void {
            const matches = self.value >= min and self.value <= max;
            if (shouldFail(negated, matches)) {
                if (negated) {
                    std.debug.print("\n  Expected {any} to NOT be between {any} and {any}\n", .{ self.value, min, max });
                } else {
                    std.debug.print("\n  Expected {any} to be between {any} and {any}\n", .{ self.value, min, max });
                }
                return error.ExpectationFailed;
            }
        }

        // =========================================================
        // String/Slice Matchers
        // =========================================================

        /// Asserts that haystack contains needle.
        pub fn contain(self: Self, needle: []const u8) !void {
            const haystack = self.value;
            const matches = std.mem.indexOf(u8, haystack, needle) != null;
            if (shouldFail(negated, matches)) {
                if (negated) {
                    std.debug.print("\n  Expected \"{s}\" to NOT contain \"{s}\"\n", .{ haystack, needle });
                } else {
                    std.debug.print("\n  Expected \"{s}\" to contain \"{s}\"\n", .{ haystack, needle });
                }
                return error.ExpectationFailed;
            }
        }

        /// Asserts that string starts with prefix.
        pub fn startWith(self: Self, prefix: []const u8) !void {
            const haystack = self.value;
            const matches = std.mem.startsWith(u8, haystack, prefix);
            if (shouldFail(negated, matches)) {
                if (negated) {
                    std.debug.print("\n  Expected \"{s}\" to NOT start with \"{s}\"\n", .{ haystack, prefix });
                } else {
                    std.debug.print("\n  Expected \"{s}\" to start with \"{s}\"\n", .{ haystack, prefix });
                }
                return error.ExpectationFailed;
            }
        }

        /// Asserts that string ends with suffix.
        pub fn endWith(self: Self, suffix: []const u8) !void {
            const haystack = self.value;
            const matches = std.mem.endsWith(u8, haystack, suffix);
            if (shouldFail(negated, matches)) {
                if (negated) {
                    std.debug.print("\n  Expected \"{s}\" to NOT end with \"{s}\"\n", .{ haystack, suffix });
                } else {
                    std.debug.print("\n  Expected \"{s}\" to end with \"{s}\"\n", .{ haystack, suffix });
                }
                return error.ExpectationFailed;
            }
        }

        /// Asserts that slice has expected length.
        pub fn haveLength(self: Self, expected_len: usize) !void {
            const actual_len = self.value.len;
            const matches = actual_len == expected_len;
            if (shouldFail(negated, matches)) {
                if (negated) {
                    std.debug.print("\n  Expected length to NOT be {d}, but it was\n", .{expected_len});
                } else {
                    std.debug.print("\n  Expected length {d}, got {d}\n", .{ expected_len, actual_len });
                }
                return error.ExpectationFailed;
            }
        }

        /// Asserts that slice is empty.
        pub fn beEmpty(self: Self) !void {
            const matches = self.value.len == 0;
            if (shouldFail(negated, matches)) {
                if (negated) {
                    std.debug.print("\n  Expected non-empty, but was empty\n", .{});
                } else {
                    std.debug.print("\n  Expected empty, got length {d}\n", .{self.value.len});
                }
                return error.ExpectationFailed;
            }
        }

        // =========================================================
        // Type Matchers
        // =========================================================

        /// Asserts that value is of expected type.
        pub fn beOfType(self: Self, comptime ExpectedType: type) !void {
            const matches = T == ExpectedType;
            _ = self;
            if (!matches) {
                std.debug.print("\n  Expected type {s}, got {s}\n", .{ @typeName(ExpectedType), @typeName(T) });
                return error.ExpectationFailed;
            }
        }

        /// Helper to determine if assertion should fail based on negation.
        fn shouldFail(is_negated: bool, matches: bool) bool {
            return (is_negated and matches) or (!is_negated and !matches);
        }
    };
}

// =========================================================================
// Tests
// =========================================================================

test "expect().to().equal" {
    try expect(@as(i32, 42)).to().equal(42);
    // String equality requires .eql() for content comparison
    try expect(@as([]const u8, "hello")).to().eql("hello");
}

test "expect().notTo().equal" {
    try expect(@as(i32, 42)).notTo().equal(43);
}

test "expect().to().beTrue" {
    try expect(true).to().beTrue();
    try expect(5 > 3).to().beTrue();
}

test "expect().to().beFalse" {
    try expect(false).to().beFalse();
    try expect(3 > 5).to().beFalse();
}

test "expect().notTo().beTrue" {
    try expect(false).notTo().beTrue();
}

test "expect().to().beNull" {
    const value: ?i32 = null;
    try expect(value).to().beNull();
}

test "expect().notTo().beNull" {
    const value: ?i32 = 42;
    try expect(value).notTo().beNull();
}

test "expect().to().beGreaterThan" {
    try expect(@as(i32, 10)).to().beGreaterThan(5);
    try expect(@as(i32, 5)).notTo().beGreaterThan(10);
}

test "expect().to().beLessThan" {
    try expect(@as(i32, 5)).to().beLessThan(10);
    try expect(@as(i32, 10)).notTo().beLessThan(5);
}

test "expect().to().beBetween" {
    try expect(@as(i32, 5)).to().beBetween(1, 10);
    try expect(@as(i32, 0)).notTo().beBetween(1, 10);
}

test "expect().to().contain" {
    try expect(@as([]const u8, "hello world")).to().contain("world");
    try expect(@as([]const u8, "hello world")).notTo().contain("foo");
}

test "expect().to().startWith" {
    try expect(@as([]const u8, "hello world")).to().startWith("hello");
    try expect(@as([]const u8, "hello world")).notTo().startWith("world");
}

test "expect().to().endWith" {
    try expect(@as([]const u8, "hello world")).to().endWith("world");
    try expect(@as([]const u8, "hello world")).notTo().endWith("hello");
}

test "expect().to().haveLength" {
    try expect(@as([]const u8, "hello")).to().haveLength(5);
    try expect(@as([]const u8, "hello")).notTo().haveLength(3);
}

test "expect().to().beEmpty" {
    try expect(@as([]const u8, "")).to().beEmpty();
    try expect(@as([]const u8, "hello")).notTo().beEmpty();
}
