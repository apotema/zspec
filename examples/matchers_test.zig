//! Matchers Example
//!
//! Demonstrates matchers in ZSpec's expect module with real typed values:
//! - toBeNull / notToBeNull: Optional value checks
//! - toHaveLength / toBeEmpty / notToBeEmpty: Length assertions
//! - Combined assertions on function return values

const std = @import("std");
const zspec = @import("zspec");
const expect = zspec.expect;

test {
    zspec.runAll(@This());
}

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

// Length Matchers
pub const Lengths = struct {
    test "toHaveLength with array" {
        const arr = [_]i32{ 1, 2, 3, 4, 5 };
        try expect.toHaveLength(&arr, 5);
    }

    test "toHaveLength with slice" {
        const slice: []const u8 = "test";
        try expect.toHaveLength(slice, 4);
    }

    test "toBeEmpty with empty slice" {
        const empty: []const u8 = "";
        try expect.toBeEmpty(empty);
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
