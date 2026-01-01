const std = @import("std");
const curl_c = @import("curl_c");
const c = curl_c.c;

pub const Response = struct {
    status: u16,
    body: []u8,
    headers: std.ArrayList(Header),
    allocator: std.mem.Allocator,

    pub const Header = struct {
        name: []const u8,
        value: []const u8,
    };

    pub fn deinit(self: *Response) void {
        self.allocator.free(self.body);
        for (self.headers.items) |header| {
            self.allocator.free(header.name);
            self.allocator.free(header.value);
        }
        self.headers.deinit(self.allocator);
    }
};

const ResponseData = struct {
    allocator: std.mem.Allocator,
    body: std.ArrayList(u8),
    headers: std.ArrayList(Response.Header),
};

fn writeCallback(ptr: [*c]u8, size: usize, nmemb: usize, userdata: ?*anyopaque) callconv(.c) usize {
    const response_data = @as(*ResponseData, @ptrCast(@alignCast(userdata.?)));
    const real_size = size * nmemb;
    const data = ptr[0..real_size];
    response_data.body.appendSlice(response_data.allocator, data) catch return 0;
    return real_size;
}

fn headerCallback(ptr: [*c]u8, size: usize, nmemb: usize, userdata: ?*anyopaque) callconv(.c) usize {
    const response_data = @as(*ResponseData, @ptrCast(@alignCast(userdata.?)));
    const real_size = size * nmemb;
    const data = ptr[0..real_size];

    // Parse header line (name: value)
    const trimmed = std.mem.trim(u8, data, " \r\n");
    if (trimmed.len == 0) return real_size;

    // Skip status line
    if (std.mem.startsWith(u8, trimmed, "HTTP/")) return real_size;

    if (std.mem.indexOf(u8, trimmed, ": ")) |colon_pos| {
        const name = response_data.allocator.dupe(u8, trimmed[0..colon_pos]) catch return 0;
        const value = response_data.allocator.dupe(u8, trimmed[colon_pos + 2 ..]) catch {
            response_data.allocator.free(name);
            return 0;
        };
        response_data.headers.append(response_data.allocator, .{
            .name = name,
            .value = value,
        }) catch {
            response_data.allocator.free(name);
            response_data.allocator.free(value);
            return 0;
        };
    }

    return real_size;
}

pub const RequestHeader = struct {
    name: []const u8,
    value: []const u8,
};

pub const Client = struct {
    pub fn init() !Client {
        const res = c.curl_global_init(c.CURL_GLOBAL_DEFAULT);
        if (res != c.CURLE_OK) {
            return error.CurlInitFailed;
        }
        return .{};
    }

    pub fn deinit(_: *Client) void {
        c.curl_global_cleanup();
    }

    pub const RequestOptions = struct {
        method: []const u8 = "GET",
        headers: []const RequestHeader = &.{},
        body: ?[]const u8 = null,
        timeout_secs: c_long = 120,
        connect_timeout_secs: c_long = 30,
        ca_cert_path: ?[]const u8 = null,
    };

    /// Make an HTTP request. The allocator should be a per-request arena
    /// that will be freed after the response is processed.
    pub fn request(_: *Client, allocator: std.mem.Allocator, url: []const u8, options: RequestOptions) !Response {
        const curl = c.curl_easy_init() orelse return error.CurlEasyInitFailed;
        defer c.curl_easy_cleanup(curl);

        // Set URL
        const url_z = try allocator.dupeZ(u8, url);
        defer allocator.free(url_z);
        _ = c.curl_easy_setopt(curl, c.CURLOPT_URL, url_z.ptr);

        // Set method
        if (std.mem.eql(u8, options.method, "POST")) {
            _ = c.curl_easy_setopt(curl, c.CURLOPT_POST, @as(c_long, 1));
        } else if (std.mem.eql(u8, options.method, "PUT")) {
            _ = c.curl_easy_setopt(curl, c.CURLOPT_CUSTOMREQUEST, "PUT");
        } else if (std.mem.eql(u8, options.method, "DELETE")) {
            _ = c.curl_easy_setopt(curl, c.CURLOPT_CUSTOMREQUEST, "DELETE");
        } else if (std.mem.eql(u8, options.method, "PATCH")) {
            _ = c.curl_easy_setopt(curl, c.CURLOPT_CUSTOMREQUEST, "PATCH");
        } else if (std.mem.eql(u8, options.method, "HEAD")) {
            _ = c.curl_easy_setopt(curl, c.CURLOPT_NOBODY, @as(c_long, 1));
        } else if (std.mem.eql(u8, options.method, "OPTIONS")) {
            _ = c.curl_easy_setopt(curl, c.CURLOPT_CUSTOMREQUEST, "OPTIONS");
        }

        // Set headers
        var header_list: ?*c.curl_slist = null;
        defer if (header_list) |list| c.curl_slist_free_all(list);

        for (options.headers) |header| {
            const header_str = try std.fmt.allocPrint(allocator, "{s}: {s}", .{ header.name, header.value });
            defer allocator.free(header_str);
            // Curl needs null-terminated string, but allocPrint returns sentinel-terminated
            const header_z = try allocator.dupeZ(u8, header_str);
            defer allocator.free(header_z);
            header_list = c.curl_slist_append(header_list, header_z.ptr);
        }
        if (header_list) |list| {
            _ = c.curl_easy_setopt(curl, c.CURLOPT_HTTPHEADER, list);
        }

        // Set body
        if (options.body) |body| {
            _ = c.curl_easy_setopt(curl, c.CURLOPT_POSTFIELDS, body.ptr);
            _ = c.curl_easy_setopt(curl, c.CURLOPT_POSTFIELDSIZE, @as(c_long, @intCast(body.len)));
        }

        // Set timeouts
        _ = c.curl_easy_setopt(curl, c.CURLOPT_TIMEOUT, options.timeout_secs);
        _ = c.curl_easy_setopt(curl, c.CURLOPT_CONNECTTIMEOUT, options.connect_timeout_secs);

        // SSL settings
        _ = c.curl_easy_setopt(curl, c.CURLOPT_SSL_VERIFYPEER, @as(c_long, 1));
        _ = c.curl_easy_setopt(curl, c.CURLOPT_SSL_VERIFYHOST, @as(c_long, 2));

        // CA certificate path - use provided path or fall back to system default
        if (options.ca_cert_path) |ca_path| {
            const ca_path_z = try allocator.dupeZ(u8, ca_path);
            defer allocator.free(ca_path_z);
            _ = c.curl_easy_setopt(curl, c.CURLOPT_CAINFO, ca_path_z.ptr);
        } else {
            // Fall back to common system paths
            _ = c.curl_easy_setopt(curl, c.CURLOPT_CAINFO, "/etc/ssl/cert.pem");
        }

        // Follow redirects
        _ = c.curl_easy_setopt(curl, c.CURLOPT_FOLLOWLOCATION, @as(c_long, 1));
        _ = c.curl_easy_setopt(curl, c.CURLOPT_MAXREDIRS, @as(c_long, 5));


        // Set up response collection
        var response_data = ResponseData{
            .allocator = allocator,
            .body = .{},
            .headers = .{},
        };
        errdefer {
            response_data.body.deinit(allocator);
            for (response_data.headers.items) |header| {
                allocator.free(header.name);
                allocator.free(header.value);
            }
            response_data.headers.deinit(allocator);
        }

        _ = c.curl_easy_setopt(curl, c.CURLOPT_WRITEFUNCTION, writeCallback);
        _ = c.curl_easy_setopt(curl, c.CURLOPT_WRITEDATA, &response_data);
        _ = c.curl_easy_setopt(curl, c.CURLOPT_HEADERFUNCTION, headerCallback);
        _ = c.curl_easy_setopt(curl, c.CURLOPT_HEADERDATA, &response_data);

        // Perform request
        const res = c.curl_easy_perform(curl);
        if (res != c.CURLE_OK) {
            const err_str = c.curl_easy_strerror(res);
            std.debug.print("curl error: {s}\n", .{err_str});
            return error.CurlRequestFailed;
        }

        // Get response code
        var response_code: c_long = 0;
        _ = c.curl_easy_getinfo(curl, c.CURLINFO_RESPONSE_CODE, &response_code);

        return Response{
            .status = @intCast(response_code),
            .body = try response_data.body.toOwnedSlice(allocator),
            .headers = response_data.headers,
            .allocator = allocator,
        };
    }
};
