//! ZSpec Test Runner
//!
//! Custom test runner that provides:
//! - beforeAll/afterAll hooks (run once per scope)
//! - before/after hooks (run before/after each test)
//! - Scoped hooks that only apply to their containing struct
//! - Colorized output
//! - Slowest tests tracking

const std = @import("std");
const builtin = @import("builtin");

const Allocator = std.mem.Allocator;

const BORDER = "=" ** 80;

// Use in custom panic handler
var current_test: ?[]const u8 = null;

pub const std_options = std.Options{
    .logFn = logging.log,
    .log_level = .debug,
};

pub fn main() !void {
    var mem: [8192]u8 = undefined;
    var fba = std.heap.FixedBufferAllocator.init(&mem);

    const allocator = fba.allocator();

    const env = Env.init(allocator);
    defer env.deinit(allocator);

    var slowest = SlowTracker.init(allocator, 5);
    defer slowest.deinit();

    var pass: usize = 0;
    var fail: usize = 0;
    var skip: usize = 0;
    var leak: usize = 0;

    const printer = Printer.init();
    printer.fmt("\r\x1b[0K", .{}); // beginning of line and clear to end of line

    // Track which scopes have had beforeAll run
    var initialized_scopes: [64]?[]const u8 = .{null} ** 64;
    var num_initialized_scopes: usize = 0;

    const scopeInitialized = struct {
        fn check(scopes: []const ?[]const u8, num: usize, scope: []const u8) bool {
            for (scopes[0..num]) |s| {
                if (s) |initialized| {
                    if (std.mem.eql(u8, initialized, scope)) {
                        return true;
                    }
                }
            }
            return false;
        }
    }.check;

    for (builtin.test_functions) |t| {
        if (isHook(t)) {
            continue;
        }

        var status = Status.pass;
        slowest.startTiming();

        const is_unnamed_test = isUnnamed(t);
        if (env.filter) |f| {
            if (!is_unnamed_test and std.mem.indexOf(u8, t.name, f) == null) {
                continue;
            }
        }

        const friendly_name = blk: {
            const name = t.name;
            var it = std.mem.splitScalar(u8, name, '.');
            while (it.next()) |value| {
                if (std.mem.eql(u8, value, "test")) {
                    const rest = it.rest();
                    break :blk if (rest.len > 0) rest else name;
                }
            }
            break :blk name;
        };

        // Run beforeAll hooks for scopes that haven't been initialized yet
        for (builtin.test_functions) |hook| {
            if (isSetup(hook)) {
                const hook_scope = getScope(hook.name);
                if (hookAppliesToTest(hook.name, t.name) and !scopeInitialized(&initialized_scopes, num_initialized_scopes, hook_scope)) {
                    hook.func() catch |err| {
                        printer.status(.fail, "\nbeforeAll \"{s}\" failed: {}\n", .{ hook.name, err });
                        status = .fail;
                        fail += 1;
                    };
                    if (num_initialized_scopes < initialized_scopes.len) {
                        initialized_scopes[num_initialized_scopes] = hook_scope;
                        num_initialized_scopes += 1;
                    }
                }
            }
        }

        current_test = friendly_name;
        std.testing.allocator_instance = .{};

        // Run before hooks that apply to this test's scope
        for (builtin.test_functions) |hook| {
            if (isBefore(hook) and hookAppliesToTest(hook.name, t.name)) {
                hook.func() catch |err| {
                    printer.status(.fail, "\nbefore \"{s}\" failed: {}\n", .{ hook.name, err });
                    status = .fail;
                    fail += 1;
                    break;
                };
            }
        }

        const result = if (status == .fail) error.BeforeHookFailed else t.func();

        // Run after hooks that apply to this test's scope (always run, even if test failed)
        for (builtin.test_functions) |hook| {
            if (isAfter(hook) and hookAppliesToTest(hook.name, t.name)) {
                hook.func() catch |err| {
                    printer.status(.fail, "\nafter \"{s}\" failed: {}\n", .{ hook.name, err });
                };
            }
        }

        current_test = null;

        const ns_taken = slowest.endTiming(friendly_name);

        if (std.testing.allocator_instance.deinit() == .leak) {
            leak += 1;
            printer.status(.fail, "\n{s}\n\"{s}\" - Memory Leak\n{s}\n", .{ BORDER, friendly_name, BORDER });
        }

        if (result) |_| {
            pass += 1;
        } else |err| switch (err) {
            error.SkipZigTest => {
                skip += 1;
                status = .skip;
            },
            error.BeforeHookFailed => {
                // Already handled above
            },
            else => {
                status = .fail;
                fail += 1;
                printer.status(
                    .fail,
                    "\n{s}\n\"{s}\" - {s}\n{s}\n",
                    .{ BORDER, friendly_name, @errorName(err), BORDER },
                );
                if (@errorReturnTrace()) |trace| {
                    SmartStackTrace.dump(trace.*);
                }
                if (env.fail_first) {
                    break;
                }
            },
        }

        if (env.verbose) {
            const ms = @as(f64, @floatFromInt(ns_taken)) / 1_000_000.0;
            printer.status(status, "{s} ({d:.2}ms)\n", .{ friendly_name, ms });
        }
    }

    // Run all afterAll hooks
    for (builtin.test_functions) |t| {
        if (isTeardown(t)) {
            t.func() catch |err| {
                printer.status(.fail, "\nafterAll \"{s}\" failed: {}\n", .{ t.name, err });
            };
        }
    }

    const total_tests = pass + fail;
    const status = if (fail == 0) Status.pass else Status.fail;
    printer.status(status, "\n{d} of {d} test{s} passed\n", .{ pass, total_tests, if (total_tests != 1) "s" else "" });
    if (skip > 0) {
        printer.status(.skip, "{d} test{s} skipped\n", .{ skip, if (skip != 1) "s" else "" });
    }
    if (leak > 0) {
        printer.status(.fail, "{d} test{s} leaked\n", .{ leak, if (leak != 1) "s" else "" });
    }
    printer.fmt("\n", .{});
    try slowest.display(printer);
    printer.fmt("\n", .{});
    std.posix.exit(if (fail == 0) 0 else 1);
}

const Printer = struct {
    fn init() Printer {
        return .{};
    }

    fn fmt(_: Printer, comptime format: []const u8, args: anytype) void {
        std.debug.print(format, args);
    }

    fn status(self: Printer, s: Status, comptime format: []const u8, args: anytype) void {
        const color = switch (s) {
            .pass => "\x1b[32m",
            .fail => "\x1b[31m",
            .skip => "\x1b[33m",
            else => "",
        };
        std.debug.print("{s}", .{color});
        std.debug.print(format, args);
        self.fmt("\x1b[0m", .{});
    }
};

const Status = enum {
    pass,
    fail,
    skip,
    text,
};

const SlowTracker = struct {
    const SlowestQueue = std.PriorityDequeue(TestInfo, void, compareTiming);
    max: usize,
    slowest: SlowestQueue,
    timer: std.time.Timer,

    fn init(alloc: Allocator, count: u32) SlowTracker {
        const timer = std.time.Timer.start() catch @panic("failed to start timer");
        var slow = SlowestQueue.init(alloc, {});
        slow.ensureTotalCapacity(count) catch @panic("OOM");
        return .{
            .max = count,
            .timer = timer,
            .slowest = slow,
        };
    }

    const TestInfo = struct {
        ns: u64,
        name: []const u8,
    };

    fn deinit(self: SlowTracker) void {
        self.slowest.deinit();
    }

    fn startTiming(self: *SlowTracker) void {
        self.timer.reset();
    }

    fn endTiming(self: *SlowTracker, test_name: []const u8) u64 {
        var timer = self.timer;
        const ns = timer.lap();

        var slow = &self.slowest;

        if (slow.count() < self.max) {
            slow.add(TestInfo{ .ns = ns, .name = test_name }) catch @panic("failed to track test timing");
            return ns;
        }

        {
            const fastest_of_the_slow = slow.peekMin() orelse unreachable;
            if (fastest_of_the_slow.ns > ns) {
                return ns;
            }
        }

        _ = slow.removeMin();
        slow.add(TestInfo{ .ns = ns, .name = test_name }) catch @panic("failed to track test timing");
        return ns;
    }

    fn display(self: *SlowTracker, printer: Printer) !void {
        var slow = self.slowest;
        const count = slow.count();
        printer.fmt("Slowest {d} test{s}: \n", .{ count, if (count != 1) "s" else "" });
        while (slow.removeMinOrNull()) |info| {
            const ms = @as(f64, @floatFromInt(info.ns)) / 1_000_000.0;
            printer.fmt("  {d:.2}ms\t{s}\n", .{ ms, info.name });
        }
    }

    fn compareTiming(_: void, a: TestInfo, b: TestInfo) std.math.Order {
        return std.math.order(a.ns, b.ns);
    }
};

const Env = struct {
    verbose: bool,
    fail_first: bool,
    filter: ?[]const u8,

    fn init(alloc: Allocator) Env {
        return .{
            .verbose = readEnvBool(alloc, "TEST_VERBOSE", true),
            .fail_first = readEnvBool(alloc, "TEST_FAIL_FIRST", false),
            .filter = readEnv(alloc, "TEST_FILTER"),
        };
    }

    fn deinit(self: Env, alloc: Allocator) void {
        if (self.filter) |f| {
            alloc.free(f);
        }
    }

    fn readEnv(alloc: Allocator, key: []const u8) ?[]const u8 {
        const v = std.process.getEnvVarOwned(alloc, key) catch |err| {
            if (err == error.EnvironmentVariableNotFound) {
                return null;
            }
            return null;
        };
        return v;
    }

    fn readEnvBool(alloc: Allocator, key: []const u8, deflt: bool) bool {
        const value = readEnv(alloc, key) orelse return deflt;
        defer alloc.free(value);
        return std.ascii.eqlIgnoreCase(value, "true");
    }
};

pub const panic = std.debug.FullPanic(struct {
    pub fn panicFn(msg: []const u8, first_trace_addr: ?usize) noreturn {
        if (current_test) |ct| {
            std.debug.print("\x1b[31m{s}\npanic running \"{s}\"\n{s}\x1b[0m\n", .{ BORDER, ct, BORDER });
        }
        std.debug.defaultPanic(msg, first_trace_addr);
    }
}.panicFn);

fn isUnnamed(t: std.builtin.TestFn) bool {
    const marker = ".test_";
    const test_name = t.name;
    const index = std.mem.indexOf(u8, test_name, marker) orelse return false;
    _ = std.fmt.parseInt(u32, test_name[index + marker.len ..], 10) catch return false;
    return true;
}

fn isSetup(t: std.builtin.TestFn) bool {
    return std.mem.endsWith(u8, t.name, "tests:beforeAll");
}

fn isTeardown(t: std.builtin.TestFn) bool {
    return std.mem.endsWith(u8, t.name, "tests:afterAll");
}

fn isBefore(t: std.builtin.TestFn) bool {
    return std.mem.endsWith(u8, t.name, "tests:before");
}

fn isAfter(t: std.builtin.TestFn) bool {
    return std.mem.endsWith(u8, t.name, "tests:after");
}

fn isHook(t: std.builtin.TestFn) bool {
    return isSetup(t) or isTeardown(t) or isBefore(t) or isAfter(t);
}

fn getScope(name: []const u8) []const u8 {
    if (std.mem.indexOf(u8, name, ".test.")) |idx| {
        return name[0..idx];
    }
    if (std.mem.indexOf(u8, name, ".test_")) |idx| {
        return name[0..idx];
    }
    return name;
}

fn hookAppliesToTest(hook_name: []const u8, test_name: []const u8) bool {
    const hook_scope = getScope(hook_name);
    const test_scope = getScope(test_name);
    return std.mem.startsWith(u8, test_scope, hook_scope);
}

const logging = struct {
    pub fn log(
        comptime _: std.log.Level,
        comptime _: @TypeOf(.enum_literal),
        comptime _: []const u8,
        _: anytype,
    ) void {}
};

/// Smart stack trace that filters out framework frames and shows source context
const SmartStackTrace = struct {
    const CONTEXT_LINES = 2; // Lines to show before/after the failure

    fn dump(trace: std.builtin.StackTrace) void {
        std.debug.print("\n\x1b[1mStack trace:\x1b[0m\n", .{});

        var first_user_frame: ?struct { file: []const u8, line: u32 } = null;

        // Print full stack trace first
        std.debug.dumpStackTrace(trace);

        // Try to find and show source context for the first user frame
        var debug_info = std.debug.getSelfDebugInfo() catch return;

        const addrs = trace.instruction_addresses[0..@min(trace.index, trace.instruction_addresses.len)];
        for (addrs) |addr| {
            if (addr == 0) continue;

            // Get symbol info using the address
            const module = debug_info.getModuleForAddress(addr) catch continue;
            const sym = module.getSymbolAtAddress(debug_info.allocator, addr -| 1) catch continue;

            if (sym.source_location) |loc| {
                // Check if this is a user frame (not framework code)
                if (!isFrameworkFrame(loc.file_name)) {
                    if (first_user_frame == null) {
                        first_user_frame = .{
                            .file = loc.file_name,
                            .line = @intCast(loc.line),
                        };
                        break;
                    }
                }
            }
        }

        // Show source context for the first user frame
        if (first_user_frame) |frame| {
            std.debug.print("\n\x1b[1mSource context:\x1b[0m\n", .{});
            printSourceContext(frame.file, frame.line);
        }
    }

    /// Checks if a stack frame is from framework code (runner, expect, zspec, std lib).
    /// Returns true for framework frames that should be filtered out of user-facing traces.
    pub fn isFrameworkFrame(file_name: []const u8) bool {
        // Filter out zspec internals
        if (std.mem.indexOf(u8, file_name, "runner.zig")) |_| return true;
        if (std.mem.indexOf(u8, file_name, "zspec.zig")) |_| return true;
        if (std.mem.indexOf(u8, file_name, "expect.zig")) |_| return true;
        // Filter out std library internals
        if (std.mem.indexOf(u8, file_name, "/zig/lib/")) |_| return true;
        return false;
    }

    fn printSourceContext(file_name: []const u8, line: u32) void {
        // Try to read the file using mmap or fallback approaches
        const file = std.fs.cwd().openFile(file_name, .{}) catch return;
        defer file.close();

        // Read file in chunks and find lines
        var buf: [8192]u8 = undefined;
        var current_line: u32 = 1;
        var line_start: usize = 0;
        var total_read: usize = 0;

        const start_line = if (line > CONTEXT_LINES) line - CONTEXT_LINES else 1;
        const end_line = line + CONTEXT_LINES;

        while (true) {
            const bytes_read = file.read(&buf) catch return;
            if (bytes_read == 0) break;

            var i: usize = 0;
            while (i < bytes_read) : (i += 1) {
                if (buf[i] == '\n') {
                    if (current_line >= start_line and current_line <= end_line) {
                        const line_content = buf[line_start..i];
                        const is_error_line = current_line == line;

                        if (is_error_line) {
                            std.debug.print("    \x1b[31m>{d:>4} | {s}\x1b[0m\n", .{ current_line, line_content });
                        } else {
                            std.debug.print("     {d:>4} | {s}\n", .{ current_line, line_content });
                        }
                    }
                    current_line += 1;
                    line_start = i + 1;

                    if (current_line > end_line) return;
                }
            }

            // Handle lines that span buffer boundaries
            if (line_start < bytes_read) {
                // Line continues in next buffer - for simplicity, just reset
                line_start = 0;
            } else {
                line_start = 0;
            }
            total_read += bytes_read;
        }
    }
};

// Unit tests for SmartStackTrace
test "isFrameworkFrame identifies runner.zig as framework" {
    try std.testing.expect(SmartStackTrace.isFrameworkFrame("/path/to/src/runner.zig"));
    try std.testing.expect(SmartStackTrace.isFrameworkFrame("runner.zig"));
}

test "isFrameworkFrame identifies zspec.zig as framework" {
    try std.testing.expect(SmartStackTrace.isFrameworkFrame("/path/to/src/zspec.zig"));
    try std.testing.expect(SmartStackTrace.isFrameworkFrame("zspec.zig"));
}

test "isFrameworkFrame identifies expect.zig as framework" {
    try std.testing.expect(SmartStackTrace.isFrameworkFrame("/path/to/src/expect.zig"));
    try std.testing.expect(SmartStackTrace.isFrameworkFrame("expect.zig"));
}

test "isFrameworkFrame identifies std library as framework" {
    try std.testing.expect(SmartStackTrace.isFrameworkFrame("/usr/lib/zig/lib/std/testing.zig"));
    try std.testing.expect(SmartStackTrace.isFrameworkFrame("/home/user/.zig/lib/std.zig"));
}

test "isFrameworkFrame returns false for user test files" {
    try std.testing.expect(!SmartStackTrace.isFrameworkFrame("/project/tests/my_test.zig"));
    try std.testing.expect(!SmartStackTrace.isFrameworkFrame("/project/src/calculator.zig"));
    try std.testing.expect(!SmartStackTrace.isFrameworkFrame("user_code.zig"));
}

test "isFrameworkFrame returns false for user files with similar names" {
    // Should not match partial names
    try std.testing.expect(!SmartStackTrace.isFrameworkFrame("/project/my_runner_test.zig"));
    try std.testing.expect(!SmartStackTrace.isFrameworkFrame("/project/expect_helper.zig"));
}
