//! Basic ZSpec Example
//!
//! Demonstrates the simplest way to write tests with ZSpec:
//! - Importing and using zspec
//! - Basic test structure
//! - Simple assertions

const std = @import("std");
const zspec = @import("zspec");
const expect = zspec.expect;

// This test block triggers ZSpec to discover all tests in this file
test {
    zspec.runAll(@This());
}

// Simple standalone tests (not in a context struct)
test "addition works correctly" {
    const result = 2 + 2;
    try expect.equal(result, 4);
}

test "strings can be compared" {
    const greeting = "hello";
    try expect.equal(greeting, "hello");
}

test "boolean conditions" {
    const x = 10;
    try expect.toBeTrue(x > 5);
    try expect.toBeFalse(x < 5);
}

// Grouping related tests in a struct (like RSpec's describe block)
pub const BasicMath = struct {
    test "multiplication" {
        try expect.equal(3 * 4, 12);
    }

    test "division" {
        try expect.equal(10 / 2, 5);
    }

    test "modulo" {
        try expect.equal(10 % 3, 1);
    }
};
