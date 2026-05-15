//! Regression test for issue #44.
//!
//! When zspec's `src/runner.zig` is used as the `.simple` mode
//! test_runner, every test using `std.testing.io` (which captures
//! `&std.testing.io_instance` at comptime — see testing.zig:34-35
//! and Io/Threaded.zig:1806) would route through a zero-initialized
//! `Io.Threaded` and deadlock on linux for any op that needs the
//! worker pool (tmpDir + writeFile, realPathFileAlloc, file-not-
//! found readFileAlloc, …). macOS happened to satisfy more zero-init
//! paths so the bug only surfaced on linux CI.
//!
//! The fix is a single-shot `testing.io_instance = .init(...)` at
//! the top of `runner.main()`. This file ensures that fix stays in
//! place: removing it puts CI back into the 6-hour-timeout regime.

const std = @import("std");
const zspec = @import("zspec");

test {
    zspec.runAll(@This());
}

pub const TestingIoTests = struct {
    test "tmpDir + writeFile + readFileAlloc round-trips via std.testing.io" {
        // The minimal sequence that deadlocked before the fix.
        var tmp = std.testing.tmpDir(.{});
        defer tmp.cleanup();

        // `tmpDir` plants the dir at `.zig-cache/tmp/<sub_path>/`;
        // build a cwd-relative path rather than going through
        // `realPathFileAlloc(io, ".")` (which has its own linux
        // deadlock signature in this same context — see #44).
        const path = try std.fs.path.join(
            std.testing.allocator,
            &.{ ".zig-cache", "tmp", &tmp.sub_path, "regression.txt" },
        );
        defer std.testing.allocator.free(path);

        const payload = "issue-44";
        try std.Io.Dir.cwd().writeFile(std.testing.io, .{
            .sub_path = path,
            .data = payload,
        });

        const read_back = try std.Io.Dir.cwd().readFileAlloc(
            std.testing.io,
            path,
            std.testing.allocator,
            .limited(1 << 14),
        );
        defer std.testing.allocator.free(read_back);

        try std.testing.expectEqualStrings(payload, read_back);
    }

    test "readFileAlloc on a missing path returns FileNotFound, doesn't hang" {
        // The other axis of the linux deadlock — readFileAlloc on a
        // path that doesn't exist. Before the fix this never returned;
        // after the fix it returns the expected error promptly.
        var tmp = std.testing.tmpDir(.{});
        defer tmp.cleanup();

        const path = try std.fs.path.join(
            std.testing.allocator,
            &.{ ".zig-cache", "tmp", &tmp.sub_path, "does-not-exist.txt" },
        );
        defer std.testing.allocator.free(path);

        const result = std.Io.Dir.cwd().readFileAlloc(
            std.testing.io,
            path,
            std.testing.allocator,
            .limited(1 << 14),
        );
        try std.testing.expectError(error.FileNotFound, result);
    }
};
