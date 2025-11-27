//! Calculator Tests using ZSpec Fluent Matchers
//!
//! Demonstrates the RSpec/Jest-like fluent assertion syntax:
//!   try expect(value).to().equal(expected);
//!   try expect(condition).to().beTrue();
//!   try expect(value).notTo().beNull();

const std = @import("std");
const zspec = @import("zspec");
const calculator = @import("calculator");

const Calculator = calculator.Calculator;
const expect = zspec.expectFluent;

test {
    zspec.runAll(@This());
}

// =============================================================================
// Basic Equality Matchers
// =============================================================================

pub const EqualityMatchers = struct {
    test "expect().to().equal() matches exact values" {
        var calc = Calculator.init();
        calc.add(42);

        try expect(calc.getResult()).to().equal(42);
    }

    test "expect().notTo().equal() matches different values" {
        var calc = Calculator.init();
        calc.add(42);

        try expect(calc.getResult()).notTo().equal(0);
        try expect(calc.getResult()).notTo().equal(100);
    }

    test "expect().to().eql() works with string content" {
        const name: []const u8 = "calculator";
        try expect(name).to().eql("calculator");
    }
};

// =============================================================================
// Boolean Matchers
// =============================================================================

pub const BooleanMatchers = struct {
    test "expect().to().beTrue() checks for true" {
        var calc = Calculator.init();
        calc.add(5);

        try expect(calc.isPositive()).to().beTrue();
    }

    test "expect().to().beFalse() checks for false" {
        var calc = Calculator.init();
        calc.subtract(5);

        try expect(calc.isPositive()).to().beFalse();
        try expect(calc.isNegative()).to().beTrue();
    }

    test "expect().notTo().beTrue() is inverse of beTrue" {
        var calc = Calculator.init();
        calc.subtract(5);

        try expect(calc.isPositive()).notTo().beTrue();
    }

    test "boolean expressions can be used directly" {
        const value: i32 = 10;
        try expect(value > 5).to().beTrue();
        try expect(value < 5).to().beFalse();
    }
};

// =============================================================================
// Comparison Matchers
// =============================================================================

pub const ComparisonMatchers = struct {
    test "expect().to().beGreaterThan() compares values" {
        var calc = Calculator.init();
        calc.add(100);

        try expect(calc.getResult()).to().beGreaterThan(50);
    }

    test "expect().to().beLessThan() compares values" {
        var calc = Calculator.init();
        calc.add(10);

        try expect(calc.getResult()).to().beLessThan(100);
    }

    test "expect().to().beGreaterThanOrEqual() includes boundary" {
        try expect(@as(i32, 10)).to().beGreaterThanOrEqual(10);
        try expect(@as(i32, 10)).to().beGreaterThanOrEqual(5);
    }

    test "expect().to().beLessThanOrEqual() includes boundary" {
        try expect(@as(i32, 10)).to().beLessThanOrEqual(10);
        try expect(@as(i32, 10)).to().beLessThanOrEqual(15);
    }

    test "expect().to().beBetween() checks range inclusive" {
        var calc = Calculator.init();
        calc.add(50);

        try expect(calc.getResult()).to().beBetween(1, 100);
        try expect(calc.getResult()).to().beBetween(50, 50); // Exact match
    }

    test "expect().notTo().beBetween() for out of range" {
        try expect(@as(i32, 0)).notTo().beBetween(1, 100);
        try expect(@as(i32, 101)).notTo().beBetween(1, 100);
    }
};

// =============================================================================
// Null Matchers
// =============================================================================

pub const NullMatchers = struct {
    test "expect().to().beNull() checks for null" {
        const value: ?i32 = null;
        try expect(value).to().beNull();
    }

    test "expect().notTo().beNull() checks for non-null" {
        const value: ?i32 = 42;
        try expect(value).notTo().beNull();
    }

    test "optional pointers can be checked for null" {
        const ptr: ?*const i32 = null;
        try expect(ptr).to().beNull();
    }
};

// =============================================================================
// String Matchers
// =============================================================================

pub const StringMatchers = struct {
    test "expect().to().contain() finds substring" {
        const message: []const u8 = "Hello, World!";
        try expect(message).to().contain("World");
        try expect(message).to().contain("Hello");
    }

    test "expect().notTo().contain() confirms absence" {
        const message: []const u8 = "Hello, World!";
        try expect(message).notTo().contain("Goodbye");
    }

    test "expect().to().startWith() checks prefix" {
        const path: []const u8 = "/usr/local/bin";
        try expect(path).to().startWith("/usr");
    }

    test "expect().to().endWith() checks suffix" {
        const filename: []const u8 = "calculator_test.zig";
        try expect(filename).to().endWith(".zig");
    }

    test "expect().notTo().startWith() confirms different prefix" {
        const path: []const u8 = "/usr/local/bin";
        try expect(path).notTo().startWith("/home");
    }

    test "expect().to().haveLength() checks string length" {
        const text: []const u8 = "hello";
        try expect(text).to().haveLength(5);
    }

    test "expect().to().beEmpty() checks for empty string" {
        const empty: []const u8 = "";
        try expect(empty).to().beEmpty();
    }

    test "expect().notTo().beEmpty() confirms non-empty" {
        const text: []const u8 = "content";
        try expect(text).notTo().beEmpty();
    }
};

// =============================================================================
// Expression Validation (Real-world Example)
// =============================================================================

pub const ExpressionValidation = struct {
    test "validates balanced parentheses" {
        try expect(calculator.validateExpression("(1+2)")).to().beTrue();
        try expect(calculator.validateExpression("((1+2)*3)")).to().beTrue();
        try expect(calculator.validateExpression("1+2")).to().beTrue();
    }

    test "rejects unbalanced parentheses" {
        try expect(calculator.validateExpression("(1+2")).to().beFalse();
        try expect(calculator.validateExpression("1+2)")).to().beFalse();
        try expect(calculator.validateExpression("((1+2)")).to().beFalse();
    }

    test "rejects empty expressions" {
        try expect(calculator.validateExpression("")).to().beFalse();
    }
};

// =============================================================================
// Number Formatting (Allocation Example)
// =============================================================================

pub const NumberFormatting = struct {
    test "formats small numbers without suffix" {
        var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
        defer arena.deinit();
        const alloc = arena.allocator();

        const result = try calculator.formatNumber(42, alloc);
        try expect(std.mem.eql(u8, result, "42")).to().beTrue();
    }

    test "formats thousands with K suffix" {
        var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
        defer arena.deinit();
        const alloc = arena.allocator();

        const result = try calculator.formatNumber(5000, alloc);
        try expect(result).to().contain("K");
        try expect(result).to().startWith("5");
    }

    test "formats millions with M suffix" {
        var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
        defer arena.deinit();
        const alloc = arena.allocator();

        const result = try calculator.formatNumber(2_500_000, alloc);
        try expect(result).to().contain("M");
    }

    test "formats billions with B suffix" {
        var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
        defer arena.deinit();
        const alloc = arena.allocator();

        const result = try calculator.formatNumber(3_000_000_000, alloc);
        try expect(result).to().contain("B");
    }
};

// =============================================================================
// Chained Calculator Operations
// =============================================================================

pub const ChainedOperations = struct {
    test "chain of additions" {
        var calc = Calculator.init();
        calc.add(10);
        calc.add(20);
        calc.add(30);

        try expect(calc.getResult()).to().equal(60);
    }

    test "mixed operations" {
        var calc = Calculator.init();
        calc.add(100);
        calc.subtract(30);
        calc.multiply(2);

        try expect(calc.getResult()).to().equal(140);
    }

    test "reset clears result" {
        var calc = Calculator.init();
        calc.add(100);
        try expect(calc.getResult()).notTo().equal(0);

        calc.reset();
        try expect(calc.getResult()).to().equal(0);
        try expect(calc.isZero()).to().beTrue();
    }
};
