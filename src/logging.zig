const std = @import("std");

/// Verbosity levels:
/// 0 = errors only, startup banner
/// 1 = basic: method, path, status, timing
/// 2 = + headers, body size
/// 3 = + body preview, SSE chunks, debug
pub const Logger = struct {
    log_requests: bool,
    log_responses: bool,
    verbosity: u8,
    mutex: std.Thread.Mutex = .{},

    pub fn init(log_requests: bool, log_responses: bool, verbosity: u8) Logger {
        return .{
            .log_requests = log_requests,
            .log_responses = log_responses,
            .verbosity = verbosity,
        };
    }

    pub fn logRequest(
        self: *Logger,
        method: []const u8,
        path: []const u8,
        headers: anytype,
        body: ?[]const u8,
    ) void {
        if (!self.log_requests or self.verbosity == 0) return;

        self.mutex.lock();
        defer self.mutex.unlock();

        const timestamp = std.time.timestamp();
        std.debug.print("\n[{d}] >>> REQUEST\n", .{timestamp});
        std.debug.print("  {s} {s}\n", .{ method, path });

        // Level 2+: show headers
        if (self.verbosity >= 2) {
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

        // Level 3: show body preview
        if (self.verbosity >= 3) {
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
        } else if (self.verbosity >= 2) {
            // Level 2: just show body size
            if (body) |b| {
                if (b.len > 0) {
                    std.debug.print("  Body: {d} bytes\n", .{b.len});
                }
            }
        }
    }

    pub fn logResponse(
        self: *Logger,
        status: u16,
        body: ?[]const u8,
        elapsed_ms: i64,
    ) void {
        if (!self.log_responses or self.verbosity == 0) return;

        self.mutex.lock();
        defer self.mutex.unlock();

        std.debug.print("[{d}ms] <<< RESPONSE {d}\n", .{ elapsed_ms, status });

        // Level 3: show body preview
        if (self.verbosity >= 3) {
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
        } else if (self.verbosity >= 2) {
            // Level 2: just show body size
            if (body) |b| {
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
        if (self.verbosity < 1) return;
        self.mutex.lock();
        defer self.mutex.unlock();
        std.debug.print("[INFO] " ++ fmt ++ "\n", args);
    }

    /// Log SSE chunk (level 3 only)
    pub fn logSSEChunk(self: *Logger, chunk_len: usize, preview: []const u8) void {
        if (self.verbosity < 3) return;
        self.mutex.lock();
        defer self.mutex.unlock();
        if (preview.len > 0) {
            std.debug.print("[SSE chunk] {d} bytes: {s}\n", .{ chunk_len, preview });
        } else {
            std.debug.print("[SSE chunk] {d} bytes: (whitespace)\n", .{chunk_len});
        }
    }

    /// Log debug info (level 3 only)
    pub fn logDebug(self: *Logger, comptime fmt: []const u8, args: anytype) void {
        if (self.verbosity < 3) return;
        self.mutex.lock();
        defer self.mutex.unlock();
        std.debug.print("[DEBUG] " ++ fmt ++ "\n", args);
    }
};
