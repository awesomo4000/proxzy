/// Example: SSE Transform with JSON Field Extraction
///
/// This demonstrates transforming SSE events by:
/// 1. Receiving complete SSE events via on_sse_event callback
/// 2. Parsing the data: field from the SSE event
/// 3. Parsing JSON from the data field
/// 4. Extracting/transforming specific fields
/// 5. Returning the modified event
///
/// Use case: Redacting sensitive fields, modifying content, logging specific data
///
/// Example SSE input:
///   data: {"model":"gpt-4","content":"Hello","usage":{"tokens":5}}
///
/// Example output (with content transform):
///   data: {"model":"gpt-4","content":"[MODIFIED] Hello","usage":{"tokens":5}}
///

const std = @import("std");
const proxzy = @import("proxzy");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Get URL from command line
    var args = try std.process.argsWithAllocator(allocator);
    defer args.deinit();
    _ = args.skip();

    const url = args.next() orelse {
        std.debug.print(
            \\Usage: proxzy-sse-json-transform <url>
            \\
            \\This example transforms SSE events containing JSON.
            \\It looks for a "content" field and prefixes it with [MODIFIED].
            \\
            \\Example with test server:
            \\  python tests/sse_json_server.py  # Start JSON SSE server
            \\  ./zig-out/bin/proxzy-sse-json-transform http://127.0.0.1:18766/stream
            \\
        , .{});
        return;
    };

    std.debug.print(
        \\
        \\  SSE JSON Transform Example
        \\  ==========================
        \\  Fetching: {s}
        \\
        \\  Transforms: Prefixes "content" field with [MODIFIED]
        \\
        \\
    , .{url});

    var client = try proxzy.Client.init();
    defer client.deinit();

    var ctx = TransformContext{
        .allocator = allocator,
        .events_transformed = 0,
        .events_passthrough = 0,
    };

    var response = try client.requestStreaming(allocator, url, .{
        .on_data = TransformContext.onData,
        .data_ctx = @ptrCast(&ctx),
        .on_sse_event = TransformContext.onSSEEvent,
        .sse_event_ctx = @ptrCast(&ctx),
    });
    defer response.deinit();

    std.debug.print(
        \\
        \\  Summary
        \\  -------
        \\  Status: {d}
        \\  Events transformed: {d}
        \\  Events passthrough: {d}
        \\
    , .{ response.status, ctx.events_transformed, ctx.events_passthrough });
}

const TransformContext = struct {
    allocator: std.mem.Allocator,
    events_transformed: u32,
    events_passthrough: u32,

    /// Transform SSE events - extract and modify JSON content field
    fn onSSEEvent(ptr: *anyopaque, event: []const u8, alloc: std.mem.Allocator) ?[]const u8 {
        const self: *TransformContext = @ptrCast(@alignCast(ptr));

        // Parse SSE event to extract data field
        const data_content = extractDataField(event) orelse {
            self.events_passthrough += 1;
            std.debug.print("[passthrough] No data field found\n", .{});
            return null;
        };

        // Try to find and transform the "content" field in JSON
        const transformed = transformContentField(alloc, data_content) catch |err| {
            self.events_passthrough += 1;
            std.debug.print("[passthrough] Transform failed: {}\n", .{err});
            return null;
        };

        if (transformed) |new_data| {
            self.events_transformed += 1;

            // Rebuild SSE event with transformed data
            const new_event = std.fmt.allocPrint(alloc, "data: {s}\n\n", .{new_data}) catch {
                return null;
            };

            std.debug.print("[transformed] {s}", .{new_event});
            return new_event;
        }

        self.events_passthrough += 1;
        return null;
    }

    fn onData(_: *anyopaque, data: []const u8) void {
        // Write to stderr (simulating client output)
        std.debug.print("{s}", .{data});
    }

    /// Extract the content after "data: " from an SSE event
    fn extractDataField(event: []const u8) ?[]const u8 {
        const prefix = "data: ";
        if (std.mem.indexOf(u8, event, prefix)) |start| {
            const data_start = start + prefix.len;
            // Find end of line
            const rest = event[data_start..];
            if (std.mem.indexOf(u8, rest, "\n")) |end| {
                return rest[0..end];
            }
            return rest;
        }
        return null;
    }

    /// Find "content" field in JSON and prefix its value with [MODIFIED]
    fn transformContentField(alloc: std.mem.Allocator, json_str: []const u8) !?[]const u8 {
        // Simple string-based transform (not full JSON parsing)
        // Looks for: "content":"value" or "content": "value"
        const content_key = "\"content\"";

        if (std.mem.indexOf(u8, json_str, content_key)) |key_pos| {
            // Find the colon and opening quote
            const after_key = json_str[key_pos + content_key.len ..];
            const colon_pos = std.mem.indexOf(u8, after_key, ":") orelse return null;
            const after_colon = after_key[colon_pos + 1 ..];

            // Skip whitespace and find opening quote
            var i: usize = 0;
            while (i < after_colon.len and (after_colon[i] == ' ' or after_colon[i] == '\t')) : (i += 1) {}

            if (i >= after_colon.len or after_colon[i] != '"') return null;

            const value_start = i + 1;
            // Find closing quote (handle escaped quotes)
            var j = value_start;
            while (j < after_colon.len) : (j += 1) {
                if (after_colon[j] == '"' and (j == value_start or after_colon[j - 1] != '\\')) {
                    break;
                }
            }
            if (j >= after_colon.len) return null;

            const original_value = after_colon[value_start..j];

            // Build new JSON with modified content
            const prefix_len = key_pos + content_key.len + colon_pos + 1 + i + 1;
            const before = json_str[0..prefix_len];
            const after = json_str[prefix_len + original_value.len ..];

            return try std.fmt.allocPrint(alloc, "{s}[MODIFIED] {s}{s}", .{
                before,
                original_value,
                after,
            });
        }

        return null;
    }
};
