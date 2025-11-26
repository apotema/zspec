//! Matchers Example
//!
//! Demonstrates all available matchers in ZSpec's expect module:
//! - equal / notEqual: Equality comparisons
//! - toBeTrue / toBeFalse: Boolean assertions
//! - toBeNull / notToBeNull: Optional value checks
//! - toBeGreaterThan / toBeLessThan: Numeric comparisons
//! - toContain: Substring search
//! - toHaveLength: Length assertions
//! - toBeEmpty / notToBeEmpty: Empty checks

const std = @import("std");
const zspec = @import("zspec");
const expect = zspec.expect;

test {
    zspec.runAll(@This());
}

// Equality Matchers
pub const Equality = struct {
    test "equal with integers" {
        try expect.equal(42, 42);
        try expect.equal(-1, -1);
        try expect.equal(0, 0);
    }

    test "equal with strings" {
        try expect.equal("hello", "hello");
        try expect.equal("", "");
    }

    test "equal with booleans" {
        try expect.equal(true, true);
        try expect.equal(false, false);
    }

    test "equal with floats" {
        try expect.equal(@as(f32, 3.14), @as(f32, 3.14));
    }

    test "notEqual with integers" {
        try expect.notEqual(1, 2);
        try expect.notEqual(-1, 1);
    }

    test "notEqual with strings" {
        try expect.notEqual("hello", "world");
    }
};

// Boolean Matchers
pub const Booleans = struct {
    test "toBeTrue with literal" {
        try expect.toBeTrue(true);
    }

    test "toBeTrue with expression" {
        try expect.toBeTrue(5 > 3);
        try expect.toBeTrue(10 == 10);
        try expect.toBeTrue("abc".len == 3);
    }

    test "toBeFalse with literal" {
        try expect.toBeFalse(false);
    }

    test "toBeFalse with expression" {
        try expect.toBeFalse(3 > 5);
        try expect.toBeFalse(1 == 2);
        try expect.toBeFalse("".len > 0);
    }
};

// Null/Optional Matchers
pub const Optionals = struct {
    test "toBeNull with null optional" {
        const value: ?i32 = null;
        try expect.toBeNull(value);
    }

    test "toBeNull with null pointer" {
        const ptr: ?*u8 = null;
        try expect.toBeNull(ptr);
    }

    test "notToBeNull with value" {
        const value: ?i32 = 42;
        try expect.notToBeNull(value);
    }

    test "notToBeNull with pointer" {
        var x: u8 = 10;
        const ptr: ?*u8 = &x;
        try expect.notToBeNull(ptr);
    }
};

// Comparison Matchers
pub const Comparisons = struct {
    test "toBeGreaterThan with integers" {
        try expect.toBeGreaterThan(10, 5);
        try expect.toBeGreaterThan(0, -1);
        try expect.toBeGreaterThan(100, 99);
    }

    test "toBeGreaterThan with floats" {
        try expect.toBeGreaterThan(@as(f64, 3.14), @as(f64, 3.13));
    }

    test "toBeLessThan with integers" {
        try expect.toBeLessThan(5, 10);
        try expect.toBeLessThan(-1, 0);
        try expect.toBeLessThan(99, 100);
    }

    test "toBeLessThan with floats" {
        try expect.toBeLessThan(@as(f64, 2.71), @as(f64, 3.14));
    }
};

// String Matchers
pub const Strings = struct {
    test "toContain finds substring at start" {
        try expect.toContain("hello world", "hello");
    }

    test "toContain finds substring at end" {
        try expect.toContain("hello world", "world");
    }

    test "toContain finds substring in middle" {
        try expect.toContain("hello world", "lo wo");
    }

    test "toContain finds single character" {
        try expect.toContain("hello", "e");
    }

    test "toContain with exact match" {
        try expect.toContain("test", "test");
    }
};

// Length Matchers
pub const Lengths = struct {
    test "toHaveLength with string" {
        try expect.toHaveLength("hello", 5);
        try expect.toHaveLength("", 0);
        try expect.toHaveLength("a", 1);
    }

    test "toHaveLength with array" {
        const arr = [_]i32{ 1, 2, 3, 4, 5 };
        try expect.toHaveLength(&arr, 5);
    }

    test "toHaveLength with slice" {
        const slice: []const u8 = "test";
        try expect.toHaveLength(slice, 4);
    }

    test "toBeEmpty with empty string" {
        try expect.toBeEmpty("");
    }

    test "toBeEmpty with empty slice" {
        const empty: []const u8 = "";
        try expect.toBeEmpty(empty);
    }

    test "notToBeEmpty with string" {
        try expect.notToBeEmpty("hello");
    }

    test "notToBeEmpty with slice" {
        const slice: []const u8 = "test";
        try expect.notToBeEmpty(slice);
    }
};

// Combined/Practical Examples
pub const PracticalExamples = struct {
    const User = struct {
        id: u32,
        name: []const u8,
        email: ?[]const u8,
        roles: []const []const u8,
    };

    fn createUser() User {
        return .{
            .id = 1,
            .name = "John Doe",
            .email = "john@example.com",
            .roles = &[_][]const u8{ "admin", "user" },
        };
    }

    fn createGuestUser() User {
        return .{
            .id = 0,
            .name = "Guest",
            .email = null,
            .roles = &[_][]const u8{},
        };
    }

    test "validate regular user" {
        const user = createUser();

        try expect.toBeGreaterThan(user.id, 0);
        try expect.notToBeEmpty(user.name);
        try expect.notToBeNull(user.email);
        try expect.toContain(user.email.?, "@");
        try expect.notToBeEmpty(user.roles);
        try expect.toHaveLength(user.roles, 2);
    }

    test "validate guest user" {
        const guest = createGuestUser();

        try expect.equal(guest.id, 0);
        try expect.toBeTrue(std.mem.eql(u8, guest.name, "Guest"));
        try expect.toBeNull(guest.email);
        try expect.toBeEmpty(guest.roles);
    }

    test "compare users" {
        const user1 = createUser();
        const user2 = createGuestUser();

        try expect.notEqual(user1.id, user2.id);
        try expect.toBeGreaterThan(user1.id, user2.id);
        try expect.toBeLessThan(user2.roles.len, user1.roles.len);
    }
};
