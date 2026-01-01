/// Example: Round-trip transform with stateful replacement
///
/// Demonstrates:
/// - Request: replaces "purple-lynx" with "[edit:color-animal-1234]"
/// - Stores the mapping in per-request state
/// - Response: replaces "[edit:color-animal-1234]" back to "purple-lynx"

const std = @import("std");
const proxzy = @import("proxzy");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var proxy = try proxzy.Proxy.init(allocator, .{
        .port = 9234,
        .upstream_url = "https://httpbin.org",
        .transform_factory = RoundtripTransform.create,
        .log_requests = false,
        .log_responses = false,
    });
    defer proxy.deinit();

    std.debug.print(
        \\
        \\  Roundtrip Transform Example
        \\  ===========================
        \\  Listening on: http://127.0.0.1:{d}
        \\
        \\  Test with:
        \\    curl -X POST http://localhost:{d}/post -d "I saw a purple-lynx in the forest"
        \\
        \\  Expected:
        \\    1. Request sends: "I saw a [edit:color-animal-1234] in the forest"
        \\    2. httpbin echoes the transformed text
        \\    3. Response shows original: "purple-lynx" restored
        \\
    , .{ proxy.port(), proxy.port() });

    try proxy.listen();
}

pub const RoundtripTransform = struct {
    allocator: std.mem.Allocator,
    original: ?[]const u8,
    placeholder: []const u8,

    const SEARCH = "purple-lynx";
    const REPLACE = "[edit:color-animal-1234]";

    pub fn create(allocator: std.mem.Allocator) ?proxzy.Transform {
        const self = allocator.create(RoundtripTransform) catch return null;
        self.* = .{
            .allocator = allocator,
            .original = null,
            .placeholder = REPLACE,
        };
        return .{
            .ptr = self,
            .onRequestFn = onRequest,
            .onResponseFn = onResponse,
        };
    }

    fn onRequest(ptr: *anyopaque, req: proxzy.Request) ?proxzy.Request {
        const self: *RoundtripTransform = @ptrCast(@alignCast(ptr));

        if (req.body == null or req.body.?.len == 0) {
            return null;
        }

        const body = req.body.?;

        // Check if body contains our search term
        if (std.mem.indexOf(u8, body, SEARCH) == null) {
            std.debug.print("[Transform] Request: no '{s}' found, passing through\n", .{SEARCH});
            return null;
        }

        // Store the original term for restoration
        self.original = SEARCH;

        // Replace search term with placeholder
        const transformed = replaceAll(self.allocator, body, SEARCH, REPLACE) catch return null;

        var new_req = req.clone() catch return null;
        new_req.body = transformed;

        std.debug.print("[Transform] Request:\n", .{});
        std.debug.print("  Original:    \"{s}\"\n", .{body});
        std.debug.print("  Transformed: \"{s}\"\n", .{transformed});
        std.debug.print("  Stored mapping: '{s}' -> '{s}'\n", .{ REPLACE, SEARCH });

        return new_req;
    }

    fn onResponse(ptr: *anyopaque, res: proxzy.Response) ?proxzy.Response {
        const self: *RoundtripTransform = @ptrCast(@alignCast(ptr));

        // Only restore if we have a stored mapping
        if (self.original == null) {
            return null;
        }

        // Check if response contains our placeholder
        if (std.mem.indexOf(u8, res.body, REPLACE)) |_| {
            std.debug.print("[Transform] Response contains placeholder - proof transform worked!\n", .{});

            // Restore original term
            const restored = replaceAll(self.allocator, res.body, REPLACE, self.original.?) catch return null;

            var new_res = res.clone() catch return null;
            new_res.body = restored;

            std.debug.print("[Transform] Response: Restored '{s}' -> '{s}'\n", .{ REPLACE, self.original.? });

            return new_res;
        } else {
            std.debug.print("[Transform] Response: no placeholder found (unexpected)\n", .{});
            return null;
        }
    }
};

fn replaceAll(allocator: std.mem.Allocator, text: []const u8, needle: []const u8, replacement: []const u8) ![]const u8 {
    var result: std.ArrayList(u8) = .{};
    var i: usize = 0;

    while (i < text.len) {
        if (i + needle.len <= text.len and std.mem.eql(u8, text[i .. i + needle.len], needle)) {
            try result.appendSlice(allocator, replacement);
            i += needle.len;
        } else {
            try result.append(allocator, text[i]);
            i += 1;
        }
    }

    return result.items;
}
