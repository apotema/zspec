//! Nested Contexts Example
//!
//! Demonstrates nested `pub const` structs for describe/context blocks.
//! Parent hooks run before child context hooks, enabling layered setup.
//!
//! Usage:
//!   zig build examples-nested

const std = @import("std");
const zspec = @import("zspec");
const expect = zspec.expect;

test {
    zspec.runAll(@This());
}

// A minimal stack for demonstration
const Stack = struct {
    items: [10]i32 = .{0} ** 10,
    top: usize = 0,

    fn push(self: *Stack, val: i32) void {
        self.items[self.top] = val;
        self.top += 1;
    }

    fn pop(self: *Stack) i32 {
        self.top -= 1;
        return self.items[self.top];
    }

    fn peek(self: *const Stack) i32 {
        return self.items[self.top - 1];
    }

    fn isEmpty(self: *const Stack) bool {
        return self.top == 0;
    }

    fn size(self: *const Stack) usize {
        return self.top;
    }
};

pub const EMPTY_STACK = struct {
    var stack: Stack = undefined;

    test "tests:before" {
        stack = Stack{};
    }

    test "is empty" {
        try expect.toBeTrue(stack.isEmpty());
    }

    test "has size zero" {
        try expect.equal(stack.size(), 0);
    }

    pub const AFTER_ONE_PUSH = struct {
        test "tests:before" {
            stack.push(42);
        }

        test "is not empty" {
            try expect.toBeFalse(stack.isEmpty());
        }

        test "has size one" {
            try expect.equal(stack.size(), 1);
        }

        test "has the pushed value on top" {
            try expect.equal(stack.peek(), 42);
        }

        pub const AFTER_SECOND_PUSH = struct {
            test "tests:before" {
                stack.push(99);
            }

            test "has size two" {
                try expect.equal(stack.size(), 2);
            }

            test "has the latest value on top" {
                try expect.equal(stack.peek(), 99);
            }

            test "pops in LIFO order" {
                try expect.equal(stack.pop(), 99);
                try expect.equal(stack.pop(), 42);
                try expect.toBeTrue(stack.isEmpty());
            }
        };
    };
};
