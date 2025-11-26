//! Hooks Example
//!
//! Demonstrates ZSpec's hook system:
//! - beforeAll: runs once before all tests in a scope
//! - afterAll: runs once after all tests in a scope
//! - before: runs before each test in a scope
//! - after: runs after each test in a scope
//!
//! Hooks are scoped - they only apply to tests within their struct.
//! Parent hooks also apply to nested structs.

const std = @import("std");
const zspec = @import("zspec");
const expect = zspec.expect;

test {
    zspec.runAll(@This());
}

// Top-level hooks apply to ALL tests in this file
var global_setup_count: usize = 0;
var global_test_count: usize = 0;

test "tests:beforeAll" {
    global_setup_count = 0;
    global_test_count = 0;
    std.debug.print("\n[Global] beforeAll - initializing\n", .{});
}

test "tests:afterAll" {
    std.debug.print("[Global] afterAll - ran {d} tests\n", .{global_test_count});
}

test "tests:before" {
    global_test_count += 1;
}

// Database simulation for demonstrating hooks
pub const Database = struct {
    var connection: ?*const u8 = null;
    var query_count: usize = 0;

    // beforeAll: Connect to database once for all tests in this struct
    test "tests:beforeAll" {
        connection = @ptrFromInt(0xDEADBEEF); // Simulated connection
        std.debug.print("  [Database] Connected\n", .{});
    }

    // afterAll: Disconnect after all tests complete
    test "tests:afterAll" {
        connection = null;
        std.debug.print("  [Database] Disconnected (ran {d} queries)\n", .{query_count});
    }

    // before: Reset query count before each test
    test "tests:before" {
        query_count = 0;
    }

    // after: Log after each test
    test "tests:after" {
        std.debug.print("    (queries this test: {d})\n", .{query_count});
    }

    test "can execute queries" {
        try expect.notToBeNull(connection);
        query_count += 1;
        try expect.equal(query_count, 1);
    }

    test "query count resets between tests" {
        // Thanks to 'before' hook, query_count is 0
        try expect.equal(query_count, 0);
        query_count += 3;
        try expect.equal(query_count, 3);
    }

    test "connection persists across tests" {
        // Thanks to 'beforeAll', connection stays open
        try expect.notToBeNull(connection);
    }
};

// Example showing hook inheritance with nested structs
pub const UserService = struct {
    var service_initialized: bool = false;

    test "tests:beforeAll" {
        service_initialized = true;
        std.debug.print("  [UserService] Initialized\n", .{});
    }

    test "tests:afterAll" {
        service_initialized = false;
        std.debug.print("  [UserService] Shutdown\n", .{});
    }

    test "service is available" {
        try expect.toBeTrue(service_initialized);
    }

    // Nested context - inherits parent hooks
    pub const Authentication = struct {
        var auth_enabled: bool = false;

        test "tests:beforeAll" {
            auth_enabled = true;
            std.debug.print("    [Authentication] Enabled\n", .{});
        }

        test "can authenticate users" {
            // Parent's beforeAll ran first, so service is initialized
            try expect.toBeTrue(service_initialized);
            // Our beforeAll ran, so auth is enabled
            try expect.toBeTrue(auth_enabled);
        }
    };
};

// Example: Using before/after for test isolation
pub const Counter = struct {
    var count: i32 = undefined;

    test "tests:before" {
        count = 0; // Fresh state for each test
    }

    test "increment" {
        count += 1;
        try expect.equal(count, 1);
    }

    test "increment multiple times" {
        count += 1;
        count += 1;
        count += 1;
        try expect.equal(count, 3);
    }

    test "decrement" {
        count -= 1;
        try expect.equal(count, -1);
    }
};
