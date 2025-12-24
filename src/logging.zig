const std = @import("std");

pub const Logger = struct {
    log_requests: bool,
    log_responses: bool,
    verbose: bool,
    mutex: std.Thread.Mutex = .{},

    pub fn init(log_requests: bool, log_responses: bool, verbose: bool) Logger {
        return .{
            .log_requests = log_requests,
            .log_responses = log_responses,
            .verbose = verbose,
        };
    }

    pub fn logRequest(
        self: *Logger,
        method: []const u8,
        path: []const u8,
        headers: anytype,
        body: ?[]const u8,
    ) void {
        if (!self.log_requests) return;

        self.mutex.lock();
        defer self.mutex.unlock();

        const timestamp = std.time.timestamp();
        std.debug.print("\n[{d}] >>> REQUEST\n", .{timestamp});
        std.debug.print("  {s} {s}\n", .{ method, path });

        if (self.verbose) {
            std.debug.print("  Headers:\n", .{});
            var iter = headers.iterator();
            while (iter.next()) |header| {
                // Mask Authorization header value
                if (std.ascii.eqlIgnoreCase(header.key, "Authorization")) {
                    std.debug.print("    {s}: [REDACTED]\n", .{header.key});
                } else {
                    std.debug.print("    {s}: {s}\n", .{ header.key, header.value });
                }
            }
        }

        if (body) |b| {
            if (b.len > 0) {
                const preview_len = @min(b.len, 500);
                std.debug.print("  Body ({d} bytes): {s}{s}\n", .{
                    b.len,
                    b[0..preview_len],
                    if (b.len > 500) "..." else "",
                });
            }
        }
    }

    pub fn logResponse(
        self: *Logger,
        status: u16,
        body: ?[]const u8,
        elapsed_ms: i64,
    ) void {
        if (!self.log_responses) return;

        self.mutex.lock();
        defer self.mutex.unlock();

        std.debug.print("[{d}ms] <<< RESPONSE {d}\n", .{ elapsed_ms, status });

        if (body) |b| {
            if (b.len > 0 and self.verbose) {
                const preview_len = @min(b.len, 500);
                std.debug.print("  Body ({d} bytes): {s}{s}\n", .{
                    b.len,
                    b[0..preview_len],
                    if (b.len > 500) "..." else "",
                });
            } else {
                std.debug.print("  Body: {d} bytes\n", .{b.len});
            }
        }
        std.debug.print("\n", .{});
    }

    pub fn logError(self: *Logger, err: anyerror, context: []const u8) void {
        _ = self;
        std.debug.print("[ERROR] {s}: {}\n", .{ context, err });
    }

    pub fn logInfo(self: *Logger, comptime fmt: []const u8, args: anytype) void {
        if (!self.verbose) return;
        self.mutex.lock();
        defer self.mutex.unlock();
        std.debug.print("[INFO] " ++ fmt ++ "\n", .{args});
    }
};
