//! JUnit XML Report Writer
//!
//! Generates JUnit XML format test reports compatible with CI systems
//! like Jenkins, GitHub Actions, GitLab CI, etc.
//!
//! JUnit XML Schema Reference:
//! https://github.com/testmoapp/junitxml

const std = @import("std");
const Allocator = std.mem.Allocator;

pub const TestResult = struct {
    name: []const u8,
    classname: []const u8,
    time_ns: u64,
    status: Status,
    failure_message: ?[]const u8 = null,
    failure_type: ?[]const u8 = null,

    pub const Status = enum {
        passed,
        failed,
        skipped,
    };
};

pub const TestSuite = struct {
    name: []const u8,
    tests: usize,
    failures: usize,
    skipped: usize,
    time_ns: u64,
    timestamp: []const u8,
};

pub const JUnitWriter = struct {
    allocator: Allocator,
    results: std.ArrayListUnmanaged(TestResult),
    suite_name: []const u8,
    start_time: i64,

    pub fn init(allocator: Allocator, suite_name: []const u8) JUnitWriter {
        return .{
            .allocator = allocator,
            .results = .{},
            .suite_name = suite_name,
            .start_time = std.time.timestamp(),
        };
    }

    pub fn deinit(self: *JUnitWriter) void {
        self.results.deinit(self.allocator);
    }

    pub fn addResult(self: *JUnitWriter, result: TestResult) !void {
        try self.results.append(self.allocator, result);
    }

    pub fn writeToFile(self: *JUnitWriter, path: []const u8) !void {
        const file = try std.fs.cwd().createFile(path, .{});
        defer file.close();

        try self.writeToFileHandle(file);
    }

    pub fn writeToFileHandle(self: *JUnitWriter, file: std.fs.File) !void {
        var total_time_ns: u64 = 0;
        var failures: usize = 0;
        var skipped: usize = 0;

        for (self.results.items) |result| {
            total_time_ns += result.time_ns;
            switch (result.status) {
                .failed => failures += 1,
                .skipped => skipped += 1,
                .passed => {},
            }
        }

        const total_time_s = @as(f64, @floatFromInt(total_time_ns)) / 1_000_000_000.0;

        // Build the XML in memory and write it all at once
        var xml = std.ArrayListUnmanaged(u8){};
        defer xml.deinit(self.allocator);

        try self.write(xml.writer(self.allocator));

        // Actually write to file
        try file.writeAll(xml.items);

        // Store totals for future reference
        _ = total_time_s;
    }

    pub fn write(self: *JUnitWriter, writer: anytype) !void {
        var total_time_ns: u64 = 0;
        var failures: usize = 0;
        var skipped: usize = 0;

        for (self.results.items) |result| {
            total_time_ns += result.time_ns;
            switch (result.status) {
                .failed => failures += 1,
                .skipped => skipped += 1,
                .passed => {},
            }
        }

        const total_time_s = @as(f64, @floatFromInt(total_time_ns)) / 1_000_000_000.0;

        // XML declaration
        try writer.writeAll("<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n");

        // Testsuites root element
        try writer.print(
            "<testsuites tests=\"{d}\" failures=\"{d}\" skipped=\"{d}\" time=\"{d:.6}\">\n",
            .{ self.results.items.len, failures, skipped, total_time_s },
        );

        // Testsuite element
        try writer.print(
            "  <testsuite name=\"{s}\" tests=\"{d}\" failures=\"{d}\" skipped=\"{d}\" time=\"{d:.6}\" timestamp=\"{d}\">\n",
            .{ self.suite_name, self.results.items.len, failures, skipped, total_time_s, self.start_time },
        );

        // Test cases
        for (self.results.items) |result| {
            const time_s = @as(f64, @floatFromInt(result.time_ns)) / 1_000_000_000.0;

            try writer.print(
                "    <testcase name=\"",
                .{},
            );
            try writeEscaped(writer, result.name);
            try writer.print(
                "\" classname=\"",
                .{},
            );
            try writeEscaped(writer, result.classname);
            try writer.print(
                "\" time=\"{d:.6}\"",
                .{time_s},
            );

            switch (result.status) {
                .passed => {
                    try writer.writeAll("/>\n");
                },
                .failed => {
                    try writer.writeAll(">\n");
                    try writer.writeAll("      <failure");
                    if (result.failure_type) |ft| {
                        try writer.writeAll(" type=\"");
                        try writeEscaped(writer, ft);
                        try writer.writeAll("\"");
                    }
                    if (result.failure_message) |msg| {
                        try writer.writeAll(" message=\"");
                        try writeEscaped(writer, msg);
                        try writer.writeAll("\"");
                    }
                    try writer.writeAll("/>\n");
                    try writer.writeAll("    </testcase>\n");
                },
                .skipped => {
                    try writer.writeAll(">\n");
                    try writer.writeAll("      <skipped/>\n");
                    try writer.writeAll("    </testcase>\n");
                },
            }
        }

        try writer.writeAll("  </testsuite>\n");
        try writer.writeAll("</testsuites>\n");
    }
};

fn writeEscaped(writer: anytype, str: []const u8) !void {
    for (str) |c| {
        switch (c) {
            '<' => try writer.writeAll("&lt;"),
            '>' => try writer.writeAll("&gt;"),
            '&' => try writer.writeAll("&amp;"),
            '"' => try writer.writeAll("&quot;"),
            '\'' => try writer.writeAll("&apos;"),
            else => {
                const bytes = [_]u8{c};
                try writer.writeAll(&bytes);
            },
        }
    }
}

// Extract classname from test name (e.g., "module.submodule.test.test name" -> "module.submodule")
pub fn extractClassname(test_name: []const u8) []const u8 {
    // Find the last ".test." or ".test_" to get the module path
    if (std.mem.lastIndexOf(u8, test_name, ".test.")) |idx| {
        return test_name[0..idx];
    }
    if (std.mem.lastIndexOf(u8, test_name, ".test_")) |idx| {
        return test_name[0..idx];
    }
    return test_name;
}

// Extract friendly test name (part after ".test.")
pub fn extractTestName(test_name: []const u8) []const u8 {
    var it = std.mem.splitScalar(u8, test_name, '.');
    while (it.next()) |value| {
        if (std.mem.eql(u8, value, "test")) {
            const rest = it.rest();
            return if (rest.len > 0) rest else test_name;
        }
    }
    return test_name;
}

test "extractClassname" {
    const expect = std.testing.expect;

    const result1 = extractClassname("example_test.Calculator.test.adds numbers");
    try expect(std.mem.eql(u8, result1, "example_test.Calculator"));

    const result2 = extractClassname("module.submodule.TestStruct.test.my test");
    try expect(std.mem.eql(u8, result2, "module.submodule.TestStruct"));

    const result3 = extractClassname("simple_test");
    try expect(std.mem.eql(u8, result3, "simple_test"));
}

test "extractTestName" {
    const expect = std.testing.expect;

    const result1 = extractTestName("example_test.Calculator.test.adds numbers");
    try expect(std.mem.eql(u8, result1, "adds numbers"));

    const result2 = extractTestName("simple_test");
    try expect(std.mem.eql(u8, result2, "simple_test"));
}

test "JUnitWriter generates valid XML" {
    const allocator = std.testing.allocator;

    var writer = JUnitWriter.init(allocator, "test-suite");
    defer writer.deinit();

    try writer.addResult(.{
        .name = "test one",
        .classname = "MyClass",
        .time_ns = 1_000_000,
        .status = .passed,
    });

    try writer.addResult(.{
        .name = "test two",
        .classname = "MyClass",
        .time_ns = 2_000_000,
        .status = .failed,
        .failure_message = "expected 1, got 2",
        .failure_type = "AssertionError",
    });

    try writer.addResult(.{
        .name = "test three",
        .classname = "MyClass",
        .time_ns = 500_000,
        .status = .skipped,
    });

    var output: std.ArrayListUnmanaged(u8) = .{};
    defer output.deinit(allocator);

    try writer.write(output.writer(allocator));

    const xml = output.items;

    // Verify XML structure
    try std.testing.expect(std.mem.indexOf(u8, xml, "<?xml version=\"1.0\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, xml, "<testsuites") != null);
    try std.testing.expect(std.mem.indexOf(u8, xml, "<testsuite name=\"test-suite\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, xml, "tests=\"3\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, xml, "failures=\"1\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, xml, "skipped=\"1\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, xml, "<testcase name=\"test one\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, xml, "<failure") != null);
    try std.testing.expect(std.mem.indexOf(u8, xml, "<skipped/>") != null);
}

test "XML escaping" {
    const allocator = std.testing.allocator;

    var writer = JUnitWriter.init(allocator, "test-suite");
    defer writer.deinit();

    try writer.addResult(.{
        .name = "test <with> \"special\" & 'chars'",
        .classname = "Test<Class>",
        .time_ns = 1_000_000,
        .status = .passed,
    });

    var output: std.ArrayListUnmanaged(u8) = .{};
    defer output.deinit(allocator);

    try writer.write(output.writer(allocator));

    const xml = output.items;

    // Verify escaping
    try std.testing.expect(std.mem.indexOf(u8, xml, "&lt;with&gt;") != null);
    try std.testing.expect(std.mem.indexOf(u8, xml, "&quot;special&quot;") != null);
    try std.testing.expect(std.mem.indexOf(u8, xml, "&amp;") != null);
    try std.testing.expect(std.mem.indexOf(u8, xml, "&apos;chars&apos;") != null);
}
