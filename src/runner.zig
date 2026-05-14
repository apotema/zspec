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
const junit = @import("junit.zig");

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

    // Use page allocator for JUnit writer (may need more memory for results)
    const page_allocator = std.heap.page_allocator;

    const env = Env.init(allocator);
    defer env.deinit(allocator);

    var slowest = SlowTracker.init(allocator, 5);
    defer slowest.deinit();

    // Initialize JUnit writer if path is configured
    var junit_writer: ?junit.JUnitWriter = if (env.junit_path != null)
        junit.JUnitWriter.init(page_allocator, "zspec")
    else
        null;
    defer if (junit_writer) |*jw| jw.deinit();

    var pass: usize = 0;
    var fail: usize = 0;
    var skip: usize = 0;
    var leak: usize = 0;

    var printer = Printer.init(env.output_file);
    defer printer.deinit();
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

        // Handle skip_ prefixed tests
        if (isSkipped(t)) {
            skip += 1;
            const skip_name = extractTestName(t.name);
            if (env.verbose) {
                printer.status(.skip, "{s} (skipped)\n", .{skip_name});
            }
            continue;
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

        // Check for memory leaks if enabled
        const leak_check = std.testing.allocator_instance.deinit();
        if (env.detect_leaks and leak_check == .leak) {
            leak += 1;
            printer.status(.fail, "\n{s}\n\"{s}\" - Memory Leak Detected\n{s}\n", .{ BORDER, friendly_name, BORDER });
            if (env.fail_on_leak) {
                status = .fail;
                fail += 1;
            }
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

        // Show test result based on verbose and failed_only settings
        const should_show = if (env.failed_only)
            status == .fail
        else
            env.verbose;

        if (should_show) {
            const ms = @as(f64, @floatFromInt(ns_taken)) / 1_000_000.0;
            printer.status(status, "{s} ({d:.2}ms)\n", .{ friendly_name, ms });
        }

        // Record result for JUnit XML output
        if (junit_writer) |*jw| {
            const junit_status: junit.TestResult.Status = switch (status) {
                .pass => .passed,
                .fail => .failed,
                .skip => .skipped,
                else => .passed,
            };

            const failure_message: ?[]const u8 = if (result) |_|
                null
            else |err| switch (err) {
                error.SkipZigTest => null,
                error.BeforeHookFailed => "before hook failed",
                else => @errorName(err),
            };

            jw.addResult(.{
                .name = friendly_name,
                .classname = junit.extractClassname(t.name),
                .time_ns = ns_taken,
                .status = junit_status,
                .failure_message = failure_message,
                .failure_type = if (failure_message != null) "TestError" else null,
            }) catch {};
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

    // Write JUnit XML report if configured
    if (junit_writer) |*jw| {
        if (env.junit_path) |path| {
            jw.writeToFile(path) catch |err| {
                printer.status(.fail, "Failed to write JUnit XML to {s}: {}\n", .{ path, err });
            };
            printer.fmt("JUnit XML report written to: {s}\n", .{path});
        }
    }

    // Exit with failure if tests failed or if leaks detected with fail_on_leak enabled
    const should_fail = fail > 0 or (env.fail_on_leak and leak > 0);
    std.process.exit(if (should_fail) 1 else 0);
}

const Printer = struct {
    // `std.fs.File` moved to `std.Io.File` in 0.16 and requires an `Io` to
    // operate. To keep the runner self-contained, the POSIX path uses raw libc
    // and the Windows path uses Win32 directly (since `std.c.O` is `void` on
    // Windows in 0.16).
    handle: ?FileHandle,

    const FileHandle = if (builtin.os.tag == .windows) std.os.windows.HANDLE else std.c.fd_t;

    fn init(output_path: ?[]const u8) Printer {
        const handle: ?FileHandle = if (output_path) |path| openForWrite(path) else null;
        return .{ .handle = handle };
    }

    fn openForWrite(path: []const u8) ?FileHandle {
        if (builtin.os.tag == .windows) {
            const w = std.os.windows;
            const k32 = struct {
                extern "kernel32" fn CreateFileW(
                    lpFileName: w.LPCWSTR,
                    dwDesiredAccess: w.DWORD,
                    dwShareMode: w.DWORD,
                    lpSecurityAttributes: ?*anyopaque,
                    dwCreationDisposition: w.DWORD,
                    dwFlagsAndAttributes: w.DWORD,
                    hTemplateFile: ?w.HANDLE,
                ) callconv(.winapi) w.HANDLE;
            };
            const GENERIC_WRITE: w.DWORD = 0x40000000;
            const CREATE_ALWAYS: w.DWORD = 2;
            const FILE_ATTRIBUTE_NORMAL: w.DWORD = 0x80;

            var path_buf_w: [std.fs.max_path_bytes]u16 = undefined;
            const path_len_w = std.unicode.wtf8ToWtf16Le(&path_buf_w, path) catch return null;
            if (path_len_w >= path_buf_w.len) return null;
            path_buf_w[path_len_w] = 0;
            const path_z: w.LPCWSTR = @ptrCast(&path_buf_w);

            const h = k32.CreateFileW(path_z, GENERIC_WRITE, 0, null, CREATE_ALWAYS, FILE_ATTRIBUTE_NORMAL, null);
            if (h == w.INVALID_HANDLE_VALUE) return null;
            return h;
        } else {
            var buf: [std.fs.max_path_bytes:0]u8 = undefined;
            if (path.len >= buf.len) return null;
            @memcpy(buf[0..path.len], path);
            buf[path.len] = 0;
            const flags: std.c.O = .{ .ACCMODE = .WRONLY, .CREAT = true, .TRUNC = true };
            const opened = std.c.open(@ptrCast(&buf), flags, @as(std.c.mode_t, 0o644));
            if (opened < 0) return null;
            return opened;
        }
    }

    fn deinit(self: *Printer) void {
        if (self.handle) |h| {
            if (builtin.os.tag == .windows) {
                std.os.windows.CloseHandle(h);
            } else {
                _ = std.c.close(h);
            }
        }
    }

    fn writeHandle(handle: FileHandle, bytes: []const u8) void {
        if (builtin.os.tag == .windows) {
            const w = std.os.windows;
            const k32 = struct {
                extern "kernel32" fn WriteFile(
                    hFile: w.HANDLE,
                    lpBuffer: [*]const u8,
                    nNumberOfBytesToWrite: w.DWORD,
                    lpNumberOfBytesWritten: *w.DWORD,
                    lpOverlapped: ?*anyopaque,
                ) callconv(.winapi) w.BOOL;
            };
            var remaining = bytes;
            while (remaining.len > 0) {
                const chunk_len: w.DWORD = @intCast(@min(remaining.len, std.math.maxInt(w.DWORD)));
                var written: w.DWORD = 0;
                const ok = k32.WriteFile(handle, remaining.ptr, chunk_len, &written, null);
                if (!ok.toBool() or written == 0) return;
                remaining = remaining[written..];
            }
        } else {
            var remaining = bytes;
            while (remaining.len > 0) {
                const n = std.c.write(handle, remaining.ptr, remaining.len);
                if (n <= 0) return;
                remaining = remaining[@intCast(n)..];
            }
        }
    }

    fn fmt(self: Printer, comptime format: []const u8, args: anytype) void {
        std.debug.print(format, args);
        // Write to file, stripping ANSI escape codes
        if (self.handle) |h| {
            var buf: [4096]u8 = undefined;
            const output = std.fmt.bufPrint(&buf, format, args) catch return;
            // Skip if it's just ANSI control sequences (starts with \x1b or \r)
            if (output.len > 0 and (output[0] == '\x1b' or output[0] == '\r')) {
                return;
            }
            writeHandle(h, output);
        }
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
        std.debug.print("\x1b[0m", .{});

        // Write to file without ANSI escape codes
        if (self.handle) |h| {
            var buf: [4096]u8 = undefined;
            const output = std.fmt.bufPrint(&buf, format, args) catch return;
            writeHandle(h, output);
        }
    }

};

const Status = enum {
    pass,
    fail,
    skip,
    text,
};

/// Monotonic timer replacement for `std.time.Timer` (removed in Zig 0.16).
/// Reads the monotonic clock directly via `std.posix.clock_gettime` on POSIX
/// targets and `QueryPerformanceCounter` on Windows.
const MonoTimer = struct {
    started_ns: u64,

    fn nowNanos() u64 {
        const native_os = @import("builtin").os.tag;
        switch (native_os) {
            .windows => {
                // `std.os.windows.QueryPerformance*` were removed in 0.16; bind
                // the syscalls directly.
                const w = std.os.windows;
                const k32 = struct {
                    extern "kernel32" fn QueryPerformanceCounter(lpPerformanceCount: *w.LARGE_INTEGER) callconv(.winapi) w.BOOL;
                    extern "kernel32" fn QueryPerformanceFrequency(lpFrequency: *w.LARGE_INTEGER) callconv(.winapi) w.BOOL;
                };
                var ticks_li: w.LARGE_INTEGER = 0;
                var freq_li: w.LARGE_INTEGER = 0;
                _ = k32.QueryPerformanceCounter(&ticks_li);
                _ = k32.QueryPerformanceFrequency(&freq_li);
                const ticks: u64 = @intCast(ticks_li);
                const freq: u64 = @intCast(freq_li);
                // Convert ticks -> nanoseconds without overflowing.
                const ns_per_s: u64 = std.time.ns_per_s;
                const seconds: u64 = ticks / freq;
                const remainder: u64 = ticks % freq;
                return seconds * ns_per_s + (remainder * ns_per_s) / freq;
            },
            else => {
                var ts: std.posix.timespec = undefined;
                _ = std.posix.system.clock_gettime(.MONOTONIC, &ts);
                const sec: u64 = @intCast(ts.sec);
                const nsec: u64 = @intCast(ts.nsec);
                return sec * std.time.ns_per_s + nsec;
            },
        }
    }

    fn start() MonoTimer {
        return .{ .started_ns = nowNanos() };
    }

    fn reset(self: *MonoTimer) void {
        self.started_ns = nowNanos();
    }

    fn lap(self: *MonoTimer) u64 {
        const now_ns = nowNanos();
        const elapsed = now_ns -% self.started_ns;
        self.started_ns = now_ns;
        return elapsed;
    }
};

const SlowTracker = struct {
    const SlowestQueue = std.PriorityDequeue(TestInfo, void, compareTiming);
    allocator: Allocator,
    max: usize,
    slowest: SlowestQueue,
    timer: MonoTimer,

    fn init(alloc: Allocator, count: u32) SlowTracker {
        const timer = MonoTimer.start();
        var slow: SlowestQueue = .empty;
        slow.ensureTotalCapacity(alloc, count) catch @panic("OOM");
        return .{
            .allocator = alloc,
            .max = count,
            .timer = timer,
            .slowest = slow,
        };
    }

    const TestInfo = struct {
        ns: u64,
        name: []const u8,
    };

    fn deinit(self: *SlowTracker) void {
        self.slowest.deinit(self.allocator);
    }

    fn startTiming(self: *SlowTracker) void {
        self.timer.reset();
    }

    fn endTiming(self: *SlowTracker, test_name: []const u8) u64 {
        var timer = self.timer;
        const ns = timer.lap();

        var slow = &self.slowest;

        if (slow.count() < self.max) {
            slow.push(self.allocator, TestInfo{ .ns = ns, .name = test_name }) catch @panic("failed to track test timing");
            return ns;
        }

        {
            const fastest_of_the_slow = slow.peekMin() orelse unreachable;
            if (fastest_of_the_slow.ns > ns) {
                return ns;
            }
        }

        _ = slow.popMin();
        slow.push(self.allocator, TestInfo{ .ns = ns, .name = test_name }) catch @panic("failed to track test timing");
        return ns;
    }

    fn display(self: *SlowTracker, printer: Printer) !void {
        var slow = self.slowest;
        const count = slow.count();
        printer.fmt("Slowest {d} test{s}: \n", .{ count, if (count != 1) "s" else "" });
        while (slow.popMin()) |info| {
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
    junit_path: ?[]const u8,
    detect_leaks: bool,
    fail_on_leak: bool,
    failed_only: bool,
    output_file: ?[]const u8,

    fn init(alloc: Allocator) Env {
        return .{
            .verbose = readEnvBool(alloc, "TEST_VERBOSE", true),
            .fail_first = readEnvBool(alloc, "TEST_FAIL_FIRST", false),
            .filter = readEnv(alloc, "TEST_FILTER"),
            .junit_path = readEnv(alloc, "TEST_JUNIT_PATH"),
            .detect_leaks = readEnvBool(alloc, "TEST_DETECT_LEAKS", true),
            .fail_on_leak = readEnvBool(alloc, "TEST_FAIL_ON_LEAK", true),
            .failed_only = readEnvBool(alloc, "TEST_FAILED_ONLY", false),
            .output_file = readEnv(alloc, "TEST_OUTPUT_FILE"),
        };
    }

    fn deinit(self: Env, alloc: Allocator) void {
        if (self.filter) |f| {
            alloc.free(f);
        }
        if (self.junit_path) |p| {
            alloc.free(p);
        }
        if (self.output_file) |f| {
            alloc.free(f);
        }
    }

    fn readEnv(alloc: Allocator, key: []const u8) ?[]const u8 {
        // `std.process.getEnvVarOwned` was removed in Zig 0.16. For a custom test
        // runner we don't have an `Io` to feed `Environ.getAlloc`, so we read
        // straight from libc's `getenv` (POSIX) or the Windows API directly
        // (the `kernel32.GetEnvironmentVariableW` wrapper was dropped in 0.16).
        const native_os = @import("builtin").os.tag;
        switch (native_os) {
            .windows => {
                const w = std.os.windows;
                const k32 = struct {
                    extern "kernel32" fn GetEnvironmentVariableW(
                        lpName: w.LPCWSTR,
                        lpBuffer: ?[*]u16,
                        nSize: w.DWORD,
                    ) callconv(.winapi) w.DWORD;
                };
                // Convert key to WTF-16, query, and convert back.
                var key_buf_w: [256]u16 = undefined;
                const key_len_w = std.unicode.wtf8ToWtf16Le(&key_buf_w, key) catch return null;
                if (key_len_w >= key_buf_w.len) return null;
                key_buf_w[key_len_w] = 0;
                const key_z: w.LPCWSTR = @ptrCast(&key_buf_w);

                var val_buf_w: [4096]u16 = undefined;
                const written = k32.GetEnvironmentVariableW(key_z, &val_buf_w, val_buf_w.len);
                if (written == 0) return null;
                if (written >= val_buf_w.len) return null;
                const wtf16 = val_buf_w[0..written];
                return std.unicode.wtf16LeToWtf8Alloc(alloc, wtf16) catch null;
            },
            else => {
                // libc `getenv` requires a null-terminated key.
                var key_buf: [256]u8 = undefined;
                if (key.len >= key_buf.len) return null;
                @memcpy(key_buf[0..key.len], key);
                key_buf[key.len] = 0;
                const c_value = std.c.getenv(@ptrCast(&key_buf)) orelse return null;
                const span = std.mem.span(c_value);
                return alloc.dupe(u8, span) catch null;
            },
        }
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

fn isSkipped(t: std.builtin.TestFn) bool {
    // Check if the test name contains "skip_" after the ".test." marker
    if (std.mem.indexOf(u8, t.name, ".test.skip_")) |_| {
        return true;
    }
    return false;
}

fn extractTestName(name: []const u8) []const u8 {
    var it = std.mem.splitScalar(u8, name, '.');
    while (it.next()) |value| {
        if (std.mem.eql(u8, value, "test")) {
            const rest = it.rest();
            return if (rest.len > 0) rest else name;
        }
    }
    return name;
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
    fn dump(trace: std.builtin.StackTrace) void {
        std.debug.print("\n\x1b[1mStack trace:\x1b[0m\n", .{});

        // Zig 0.16 split `std.builtin.StackTrace` (handed to us by failing
        // tests) from `std.debug.StackTrace` (consumed by `dumpStackTrace`).
        // Build the debug variant before dumping.
        const valid_addrs = trace.instruction_addresses[0..@min(trace.index, trace.instruction_addresses.len)];
        const debug_trace: std.debug.StackTrace = .{
            .return_addresses = valid_addrs,
            .skipped = .none,
        };
        std.debug.dumpStackTrace(&debug_trace);

        // The Zig 0.15 source-context viewer relied on
        // `std.debug.SelfInfo.getModuleForAddress` plus `std.fs.cwd().openFile`,
        // both of which were reworked in 0.16. The default stack trace already
        // prints source lines, so we no longer duplicate that here.
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
