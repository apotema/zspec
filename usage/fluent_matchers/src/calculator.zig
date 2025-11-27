//! Simple Calculator Module
//!
//! Example code for demonstrating ZSpec fluent matchers.

const std = @import("std");

pub const Calculator = struct {
    result: i64,

    pub fn init() Calculator {
        return .{
            .result = 0,
        };
    }

    pub fn add(self: *Calculator, value: i64) void {
        self.result += value;
    }

    pub fn subtract(self: *Calculator, value: i64) void {
        self.result -= value;
    }

    pub fn multiply(self: *Calculator, value: i64) void {
        self.result *= value;
    }

    pub fn divide(self: *Calculator, value: i64) !void {
        if (value == 0) {
            return error.DivisionByZero;
        }
        self.result = @divTrunc(self.result, value);
    }

    pub fn reset(self: *Calculator) void {
        self.result = 0;
    }

    pub fn getResult(self: Calculator) i64 {
        return self.result;
    }

    pub fn isPositive(self: Calculator) bool {
        return self.result > 0;
    }

    pub fn isNegative(self: Calculator) bool {
        return self.result < 0;
    }

    pub fn isZero(self: Calculator) bool {
        return self.result == 0;
    }
};

/// Validates a mathematical expression string
pub fn validateExpression(expr: []const u8) bool {
    if (expr.len == 0) return false;

    // Check for balanced parentheses
    var depth: i32 = 0;
    for (expr) |char| {
        if (char == '(') depth += 1;
        if (char == ')') depth -= 1;
        if (depth < 0) return false;
    }

    return depth == 0;
}

/// Formats a number with appropriate suffix
pub fn formatNumber(value: i64, allocator: std.mem.Allocator) ![]u8 {
    const abs_value: u64 = if (value < 0) @intCast(-value) else @intCast(value);
    const sign: []const u8 = if (value < 0) "-" else "";

    if (abs_value >= 1_000_000_000) {
        return std.fmt.allocPrint(allocator, "{s}{d}B", .{ sign, abs_value / 1_000_000_000 });
    } else if (abs_value >= 1_000_000) {
        return std.fmt.allocPrint(allocator, "{s}{d}M", .{ sign, abs_value / 1_000_000 });
    } else if (abs_value >= 1_000) {
        return std.fmt.allocPrint(allocator, "{s}{d}K", .{ sign, abs_value / 1_000 });
    } else {
        return std.fmt.allocPrint(allocator, "{d}", .{value});
    }
}
