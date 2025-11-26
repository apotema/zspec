//! Let Memoization Example
//!
//! Demonstrates ZSpec's lazy memoization feature (similar to RSpec's `let`):
//! - Let(T, init_fn): Memoized value computed once per test
//! - LetAlloc(T, init_fn): Memoized value that requires an allocator
//!
//! Key behaviors:
//! - Value is computed lazily on first .get() call
//! - Same value is returned on subsequent .get() calls within a test
//! - Must call .reset() in after hook to clear between tests

const std = @import("std");
const zspec = @import("zspec");
const expect = zspec.expect;

test {
    zspec.runAll(@This());
}

// Example: Simple memoized value
pub const SimpleLet = struct {
    var computation_count: usize = 0;

    fn computeExpensiveValue() i32 {
        computation_count += 1;
        // Simulate expensive computation
        return 42 * 2;
    }

    const expensive_value = zspec.Let(i32, computeExpensiveValue);

    test "tests:before" {
        computation_count = 0;
    }

    test "tests:after" {
        expensive_value.reset(); // Important: reset for next test
    }

    test "value is computed lazily" {
        // Not computed yet
        try expect.equal(computation_count, 0);

        // First access triggers computation
        const val = expensive_value.get();
        try expect.equal(val, 84);
        try expect.equal(computation_count, 1);
    }

    test "value is memoized within a test" {
        // Call get() multiple times
        _ = expensive_value.get();
        _ = expensive_value.get();
        _ = expensive_value.get();

        // Should only compute once
        try expect.equal(computation_count, 1);
    }

    test "value resets between tests" {
        // Fresh computation for this test (thanks to after hook reset)
        try expect.equal(computation_count, 0);
        _ = expensive_value.get();
        try expect.equal(computation_count, 1);
    }
};

// Example: Memoized struct instance
pub const StructLet = struct {
    const User = struct {
        id: u32,
        name: []const u8,
        active: bool,

        fn init(id: u32, name: []const u8) User {
            return .{ .id = id, .name = name, .active = true };
        }
    };

    fn createTestUser() User {
        return User.init(1, "test_user");
    }

    const test_user = zspec.Let(User, createTestUser);

    test "tests:after" {
        test_user.reset();
    }

    test "user has expected properties" {
        const user = test_user.get();
        try expect.equal(user.id, 1);
        try expect.toBeTrue(std.mem.eql(u8, user.name, "test_user"));
        try expect.toBeTrue(user.active);
    }

    test "same user instance returned" {
        const user1 = test_user.get();
        const user2 = test_user.get();
        try expect.equal(user1.id, user2.id);
        try expect.toBeTrue(std.mem.eql(u8, user1.name, user2.name));
    }
};

// Example: Using LetAlloc for heap allocations
pub const AllocLet = struct {
    const DynamicBuffer = struct {
        data: []i32,
        allocator: std.mem.Allocator,

        fn deinit(self: DynamicBuffer) void {
            self.allocator.free(self.data);
        }
    };

    fn createDynamicBuffer(alloc: std.mem.Allocator) DynamicBuffer {
        const data = alloc.alloc(i32, 5) catch @panic("alloc failed");
        @memcpy(data, &[_]i32{ 1, 2, 3, 4, 5 });
        return .{ .data = data, .allocator = alloc };
    }

    const dynamic_buffer = zspec.LetAlloc(DynamicBuffer, createDynamicBuffer);

    test "tests:after" {
        // For LetAlloc, free the resource before reset
        if (dynamic_buffer.get(zspec.allocator).data.len > 0) {
            dynamic_buffer.get(zspec.allocator).deinit();
        }
        dynamic_buffer.reset();
    }

    test "buffer is initialized with values" {
        const buf = dynamic_buffer.get(zspec.allocator);
        try expect.equal(buf.data.len, 5);
        try expect.equal(buf.data[0], 1);
        try expect.equal(buf.data[4], 5);
    }

    test "buffer is memoized" {
        const buf1 = dynamic_buffer.get(zspec.allocator);
        const buf2 = dynamic_buffer.get(zspec.allocator);
        try expect.equal(buf1.data.len, buf2.data.len);
    }
};

// Example: Multiple let values in one context
pub const MultipleLets = struct {
    fn createConfig() struct { debug: bool, max_retries: u8 } {
        return .{ .debug = true, .max_retries = 3 };
    }

    fn createTimeout() u64 {
        return 5000; // 5 seconds in ms
    }

    const config = zspec.Let(@TypeOf(createConfig()), createConfig);
    const timeout = zspec.Let(u64, createTimeout);

    test "tests:after" {
        config.reset();
        timeout.reset();
    }

    test "config values" {
        const cfg = config.get();
        try expect.toBeTrue(cfg.debug);
        try expect.equal(cfg.max_retries, 3);
    }

    test "timeout value" {
        try expect.equal(timeout.get(), 5000);
    }

    test "both values available together" {
        const cfg = config.get();
        const t = timeout.get();
        try expect.toBeTrue(cfg.debug);
        try expect.equal(t, 5000);
    }
};
