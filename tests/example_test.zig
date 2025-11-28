//! Example tests demonstrating ZSpec features

const std = @import("std");
const zspec = @import("zspec");
const expect = zspec.expect;
const allocator = zspec.allocator;

test {
    zspec.runAll(@This());
}

// Top-level hooks apply to all tests
var total_tests: usize = 0;

test "tests:beforeAll" {
    total_tests = 0;
    std.debug.print("\n[Calculator Tests] Starting...\n", .{});
}

test "tests:afterAll" {
    std.debug.print("[Calculator Tests] Completed {d} tests\n", .{total_tests});
}

test "tests:before" {
    total_tests += 1;
}

// Example: Simple Calculator
const Calculator = struct {
    value: i32,

    pub fn init() Calculator {
        return .{ .value = 0 };
    }

    pub fn add(self: *Calculator, n: i32) void {
        self.value += n;
    }

    pub fn subtract(self: *Calculator, n: i32) void {
        self.value -= n;
    }

    pub fn multiply(self: *Calculator, n: i32) void {
        self.value *= n;
    }

    pub fn reset(self: *Calculator) void {
        self.value = 0;
    }
};

pub const ADD = struct {
    var calc: Calculator = undefined;

    test "tests:before" {
        calc = Calculator.init();
    }

    test "adds positive numbers" {
        calc.add(5);
        try expect.equal(calc.value, 5);
    }

    test "adds negative numbers" {
        calc.add(-3);
        try expect.equal(calc.value, -3);
    }

    test "adds zero" {
        calc.add(0);
        try expect.equal(calc.value, 0);
    }

    test "adds multiple times" {
        calc.add(10);
        calc.add(20);
        calc.add(30);
        try expect.equal(calc.value, 60);
    }
};

pub const SUBTRACT = struct {
    var calc: Calculator = undefined;

    test "tests:before" {
        calc = Calculator.init();
        calc.value = 100;
    }

    test "subtracts positive numbers" {
        calc.subtract(30);
        try expect.equal(calc.value, 70);
    }

    test "subtracts negative numbers" {
        calc.subtract(-20);
        try expect.equal(calc.value, 120);
    }

    test "can go negative" {
        calc.subtract(150);
        try expect.equal(calc.value, -50);
    }
};

pub const MULTIPLY = struct {
    var calc: Calculator = undefined;

    test "tests:before" {
        calc = Calculator.init();
        calc.value = 10;
    }

    test "multiplies by positive" {
        calc.multiply(5);
        try expect.equal(calc.value, 50);
    }

    test "multiplies by zero" {
        calc.multiply(0);
        try expect.equal(calc.value, 0);
    }

    test "multiplies by negative" {
        calc.multiply(-3);
        try expect.equal(calc.value, -30);
    }
};

pub const RESET = struct {
    var calc: Calculator = undefined;

    test "tests:beforeAll" {
        std.debug.print("  [RESET] Setting up...\n", .{});
    }

    test "tests:afterAll" {
        std.debug.print("  [RESET] Done!\n", .{});
    }

    test "tests:before" {
        calc = Calculator.init();
        calc.value = 999;
    }

    test "resets to zero" {
        calc.reset();
        try expect.equal(calc.value, 0);
    }
};

// Example using Let for memoization
pub const LET_EXAMPLE = struct {
    fn createExpensiveValue() i32 {
        // Simulates expensive computation
        return 42 * 2;
    }

    const expensive_value = zspec.Let(i32, createExpensiveValue);

    test "tests:after" {
        expensive_value.reset();
    }

    test "let memoizes the value" {
        const first = expensive_value.get();
        const second = expensive_value.get();
        try expect.equal(first, 84);
        try expect.equal(second, 84);
    }
};

// Example of nested context
pub const STRING_UTILS = struct {
    pub const UPPERCASE = struct {
        test "converts to uppercase" {
            // Just demonstrating nested structure
            try expect.toBeTrue(true);
        }
    };

    pub const LOWERCASE = struct {
        test "converts to lowercase" {
            try expect.toBeTrue(true);
        }
    };
};

// Example: Skipping tests with skip_ prefix
pub const SKIP_EXAMPLE = struct {
    test "skip_this test is work in progress" {
        // This test will be skipped and not run
        try expect.toBeTrue(false); // Would fail if run
    }

    test "skip_another skipped test" {
        // This test will also be skipped
        unreachable;
    }

    test "this test runs normally" {
        try expect.toBeTrue(true);
    }
};

// Testing the expect matchers
pub const MATCHERS = struct {
    test "equal works" {
        try expect.equal(1, 1);
        try expect.equal("hello", "hello");
    }

    test "notEqual works" {
        try expect.notEqual(1, 2);
    }

    test "toBeTrue works" {
        try expect.toBeTrue(true);
        try expect.toBeTrue(5 > 3);
    }

    test "toBeFalse works" {
        try expect.toBeFalse(false);
        try expect.toBeFalse(3 > 5);
    }

    test "toBeGreaterThan works" {
        try expect.toBeGreaterThan(10, 5);
    }

    test "toBeLessThan works" {
        try expect.toBeLessThan(5, 10);
    }

    test "toContain works" {
        try expect.toContain("hello world", "world");
    }

    test "toHaveLength works" {
        try expect.toHaveLength("hello", 5);
    }

    test "toBeEmpty works" {
        try expect.toBeEmpty("");
    }

    test "notToBeEmpty works" {
        try expect.notToBeEmpty("hi");
    }
};
