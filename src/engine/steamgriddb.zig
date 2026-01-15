const std = @import("std");
const http = std.http;

// ═══════════════════════════════════════════════════════════════════════════════
// STEAMGRIDDB INTEGRATION
// ═══════════════════════════════════════════════════════════════════════════════
//
// SteamGridDB (https://www.steamgriddb.com/) provides:
//   - Grid images (600x900, library covers)
//   - Hero images (1920x620, library backgrounds)
//   - Logo images (transparent game logos)
//   - Icon images (app icons)
//
// API: https://www.steamgriddb.com/api/v2
// Free tier: 1000 requests/day
//
// ═══════════════════════════════════════════════════════════════════════════════

const API_BASE = "https://www.steamgriddb.com/api/v2";

/// Image types available from SteamGridDB
pub const ImageType = enum {
    grid, // 600x900 vertical cover
    hero, // 1920x620 horizontal banner
    logo, // Transparent logo
    icon, // Square icon

    pub fn toPath(self: ImageType) []const u8 {
        return switch (self) {
            .grid => "grids",
            .hero => "heroes",
            .logo => "logos",
            .icon => "icons",
        };
    }
};

/// Image style preferences
pub const ImageStyle = enum {
    alternate,
    blurred,
    white_logo,
    material,
    no_logo,
    any,

    pub fn toQuery(self: ImageStyle) ?[]const u8 {
        return switch (self) {
            .alternate => "alternate",
            .blurred => "blurred",
            .white_logo => "white_logo",
            .material => "material",
            .no_logo => "no_logo",
            .any => null,
        };
    }
};

/// Image dimensions
pub const Dimensions = enum {
    dim_460x215,
    dim_920x430,
    dim_600x900,
    dim_342x482,
    dim_660x930,
    dim_512x512,
    dim_1024x1024,
    any,

    pub fn toQuery(self: Dimensions) ?[]const u8 {
        return switch (self) {
            .dim_460x215 => "460x215",
            .dim_920x430 => "920x430",
            .dim_600x900 => "600x900",
            .dim_342x482 => "342x482",
            .dim_660x930 => "660x930",
            .dim_512x512 => "512x512",
            .dim_1024x1024 => "1024x1024",
            .any => null,
        };
    }
};

/// Search result from game search
pub const GameResult = struct {
    id: u32,
    name: []const u8,
    types: []const []const u8,
    verified: bool,

    pub fn deinit(self: *GameResult, allocator: std.mem.Allocator) void {
        allocator.free(self.name);
        for (self.types) |t| allocator.free(t);
        if (self.types.len > 0) allocator.free(self.types);
    }
};

/// Image result
pub const ImageResult = struct {
    id: u32,
    url: []const u8,
    thumb_url: []const u8,
    width: u32,
    height: u32,
    style: []const u8,
    mime: []const u8,
    score: i32,

    pub fn deinit(self: *ImageResult, allocator: std.mem.Allocator) void {
        allocator.free(self.url);
        allocator.free(self.thumb_url);
        allocator.free(self.style);
        allocator.free(self.mime);
    }
};

/// SteamGridDB client
pub const SteamGridDBClient = struct {
    allocator: std.mem.Allocator,
    api_key: []const u8,
    cache_dir: []const u8,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator, api_key: ?[]const u8) !Self {
        // Get API key from param or environment
        const key = api_key orelse std.posix.getenv("STEAMGRIDDB_API_KEY") orelse {
            std.log.warn("SteamGridDB: No API key provided (set STEAMGRIDDB_API_KEY)", .{});
            return error.NoApiKey;
        };

        const cache_dir = try getCacheDir(allocator);

        // Ensure cache directories exist
        std.fs.makeDirAbsolute(cache_dir) catch |err| {
            if (err != error.PathAlreadyExists) return err;
        };

        for ([_][]const u8{ "grids", "heroes", "logos", "icons" }) |subdir| {
            const sub_path = try std.fmt.allocPrint(allocator, "{s}/{s}", .{ cache_dir, subdir });
            defer allocator.free(sub_path);
            std.fs.makeDirAbsolute(sub_path) catch |err| {
                if (err != error.PathAlreadyExists) return err;
            };
        }

        return Self{
            .allocator = allocator,
            .api_key = try allocator.dupe(u8, key),
            .cache_dir = cache_dir,
        };
    }

    pub fn deinit(self: *Self) void {
        self.allocator.free(self.api_key);
        self.allocator.free(self.cache_dir);
    }

    /// Search for a game by name
    pub fn searchGame(self: *Self, name: []const u8) ![]GameResult {
        const encoded_name = try urlEncode(self.allocator, name);
        defer self.allocator.free(encoded_name);

        const url = try std.fmt.allocPrint(
            self.allocator,
            "{s}/search/autocomplete/{s}",
            .{ API_BASE, encoded_name },
        );
        defer self.allocator.free(url);

        const response = try self.apiRequest(url);
        defer self.allocator.free(response);

        return self.parseGameResults(response);
    }

    /// Get images for a game by SteamGridDB ID
    pub fn getImages(
        self: *Self,
        game_id: u32,
        image_type: ImageType,
        style: ImageStyle,
        dimensions: Dimensions,
    ) ![]ImageResult {
        var url_buf: std.ArrayList(u8) = .{};
        defer url_buf.deinit(self.allocator);

        try url_buf.appendSlice(self.allocator, API_BASE);
        try url_buf.appendSlice(self.allocator, "/");
        try url_buf.appendSlice(self.allocator, image_type.toPath());
        try url_buf.appendSlice(self.allocator, "/game/");

        var id_buf: [16]u8 = undefined;
        const id_str = std.fmt.bufPrint(&id_buf, "{d}", .{game_id}) catch return error.FormatFailed;
        try url_buf.appendSlice(self.allocator, id_str);

        // Add query params
        var has_param = false;

        if (style.toQuery()) |s| {
            try url_buf.appendSlice(self.allocator, if (has_param) "&" else "?");
            try url_buf.appendSlice(self.allocator, "styles=");
            try url_buf.appendSlice(self.allocator, s);
            has_param = true;
        }

        if (dimensions.toQuery()) |d| {
            try url_buf.appendSlice(self.allocator, if (has_param) "&" else "?");
            try url_buf.appendSlice(self.allocator, "dimensions=");
            try url_buf.appendSlice(self.allocator, d);
            has_param = true;
        }

        const response = try self.apiRequest(url_buf.items);
        defer self.allocator.free(response);

        return self.parseImageResults(response);
    }

    /// Get images for a Steam game by AppID
    pub fn getImagesByAppId(
        self: *Self,
        app_id: u32,
        image_type: ImageType,
    ) ![]ImageResult {
        var url_buf: [256]u8 = undefined;
        const url = std.fmt.bufPrint(
            &url_buf,
            "{s}/{s}/steam/{d}",
            .{ API_BASE, image_type.toPath(), app_id },
        ) catch return error.FormatFailed;

        const response = try self.apiRequest(url);
        defer self.allocator.free(response);

        return self.parseImageResults(response);
    }

    /// Download an image to the cache
    pub fn downloadImage(
        self: *Self,
        image: *const ImageResult,
        image_type: ImageType,
        game_id: u32,
    ) ![]const u8 {
        // Determine file extension from mime type
        const ext = getMimeExtension(image.mime);

        // Build cache path
        const cache_path = try std.fmt.allocPrint(
            self.allocator,
            "{s}/{s}/{d}_{d}{s}",
            .{ self.cache_dir, image_type.toPath(), game_id, image.id, ext },
        );

        // Check if already cached
        if (std.fs.accessAbsolute(cache_path, .{})) {
            std.log.debug("SteamGridDB: Using cached image: {s}", .{cache_path});
            return cache_path;
        } else |_| {}

        // Download the image
        std.log.info("SteamGridDB: Downloading {s}", .{image.url});

        var client = http.Client{ .allocator = self.allocator };
        defer client.deinit();

        // Parse URI
        const uri = try std.Uri.parse(image.url);

        // Zig 0.15.x: Use request/response API
        var req = try client.request(.GET, uri, .{});
        defer req.deinit();

        // Send the request
        try req.sendBodiless();

        // Receive response head
        var redirect_buffer: [8192]u8 = undefined;
        var response = try req.receiveHead(&redirect_buffer);

        if (response.head.status != .ok) {
            return error.DownloadFailed;
        }

        // Zig 0.15.x: Read response body using the response reader
        var transfer_buffer: [8192]u8 = undefined;
        const reader = response.reader(&transfer_buffer);
        const body = try reader.allocRemaining(self.allocator, std.Io.Limit.limited(10 * 1024 * 1024));
        defer self.allocator.free(body);

        // Write to cache
        const file = try std.fs.createFileAbsolute(cache_path, .{});
        defer file.close();
        try file.writeAll(body);

        std.log.info("SteamGridDB: Saved to {s}", .{cache_path});

        return cache_path;
    }

    /// Get the cached image path if it exists
    pub fn getCachedImage(
        self: *Self,
        image_type: ImageType,
        game_id: u32,
    ) ?[]const u8 {
        const prefix = std.fmt.allocPrint(
            self.allocator,
            "{s}/{s}/{d}_",
            .{ self.cache_dir, image_type.toPath(), game_id },
        ) catch return null;
        defer self.allocator.free(prefix);

        const type_dir = std.fmt.allocPrint(
            self.allocator,
            "{s}/{s}",
            .{ self.cache_dir, image_type.toPath() },
        ) catch return null;
        defer self.allocator.free(type_dir);

        var dir = std.fs.openDirAbsolute(type_dir, .{ .iterate = true }) catch return null;
        defer dir.close();

        var iter = dir.iterate();
        while (iter.next() catch return null) |entry| {
            if (std.mem.startsWith(u8, entry.name, std.fs.path.basename(prefix))) {
                return std.fmt.allocPrint(
                    self.allocator,
                    "{s}/{s}",
                    .{ type_dir, entry.name },
                ) catch return null;
            }
        }

        return null;
    }

    fn apiRequest(self: *Self, url: []const u8) ![]const u8 {
        var client = http.Client{ .allocator = self.allocator };
        defer client.deinit();

        // Build authorization header
        const auth_header = try std.fmt.allocPrint(self.allocator, "Bearer {s}", .{self.api_key});
        defer self.allocator.free(auth_header);

        // Parse URI
        const uri = try std.Uri.parse(url);

        // Zig 0.15.x: Use request/response API
        var req = try client.request(.GET, uri, .{
            .extra_headers = &.{
                .{ .name = "Authorization", .value = auth_header },
            },
        });
        defer req.deinit();

        // Send the request (no body for GET)
        try req.sendBodiless();

        // Receive response head
        var redirect_buffer: [8192]u8 = undefined;
        var response = try req.receiveHead(&redirect_buffer);

        if (response.head.status != .ok) {
            std.log.warn("SteamGridDB: API returned {}", .{response.head.status});
            return error.ApiError;
        }

        // Zig 0.15.x: Read response body using the response reader
        var transfer_buffer: [8192]u8 = undefined;
        const reader = response.reader(&transfer_buffer);
        const body = try reader.allocRemaining(self.allocator, std.Io.Limit.limited(1024 * 1024));

        return body;
    }

    fn parseGameResults(self: *Self, response: []const u8) ![]GameResult {
        var parsed = std.json.parseFromSlice(std.json.Value, self.allocator, response, .{}) catch |err| {
            std.log.warn("SteamGridDB: Failed to parse response: {}", .{err});
            return error.ParseError;
        };
        defer parsed.deinit();

        if (parsed.value != .object) return error.InvalidResponse;

        const data = parsed.value.object.get("data") orelse return error.InvalidResponse;
        if (data != .array) return error.InvalidResponse;

        var results: std.ArrayList(GameResult) = .{};
        errdefer results.deinit(self.allocator);

        for (data.array.items) |item| {
            if (item != .object) continue;
            const obj = item.object;

            const id = obj.get("id") orelse continue;
            if (id != .integer) continue;

            const name = obj.get("name") orelse continue;
            if (name != .string) continue;

            var verified = false;
            if (obj.get("verified")) |v| {
                if (v == .bool) verified = v.bool;
            }

            var types: std.ArrayList([]const u8) = .{};
            if (obj.get("types")) |t| {
                if (t == .array) {
                    for (t.array.items) |type_item| {
                        if (type_item == .string) {
                            try types.append(self.allocator, try self.allocator.dupe(u8, type_item.string));
                        }
                    }
                }
            }

            try results.append(self.allocator, .{
                .id = @intCast(id.integer),
                .name = try self.allocator.dupe(u8, name.string),
                .types = try types.toOwnedSlice(self.allocator),
                .verified = verified,
            });
        }

        return results.toOwnedSlice(self.allocator);
    }

    fn parseImageResults(self: *Self, response: []const u8) ![]ImageResult {
        var parsed = std.json.parseFromSlice(std.json.Value, self.allocator, response, .{}) catch |err| {
            std.log.warn("SteamGridDB: Failed to parse response: {}", .{err});
            return error.ParseError;
        };
        defer parsed.deinit();

        if (parsed.value != .object) return error.InvalidResponse;

        const data = parsed.value.object.get("data") orelse return error.InvalidResponse;
        if (data != .array) return error.InvalidResponse;

        var results: std.ArrayList(ImageResult) = .{};
        errdefer results.deinit(self.allocator);

        for (data.array.items) |item| {
            if (item != .object) continue;
            const obj = item.object;

            const id = obj.get("id") orelse continue;
            const url = obj.get("url") orelse continue;
            const thumb = obj.get("thumb") orelse continue;
            const width = obj.get("width") orelse continue;
            const height = obj.get("height") orelse continue;

            if (id != .integer or url != .string or thumb != .string or
                width != .integer or height != .integer) continue;

            var style: []const u8 = "";
            if (obj.get("style")) |s| {
                if (s == .string) style = try self.allocator.dupe(u8, s.string);
            }

            var mime: []const u8 = "image/png";
            if (obj.get("mime")) |m| {
                if (m == .string) mime = try self.allocator.dupe(u8, m.string);
            }

            var score: i32 = 0;
            if (obj.get("score")) |sc| {
                if (sc == .integer) score = @intCast(sc.integer);
            }

            try results.append(self.allocator, .{
                .id = @intCast(id.integer),
                .url = try self.allocator.dupe(u8, url.string),
                .thumb_url = try self.allocator.dupe(u8, thumb.string),
                .width = @intCast(width.integer),
                .height = @intCast(height.integer),
                .style = style,
                .mime = mime,
                .score = score,
            });
        }

        return results.toOwnedSlice(self.allocator);
    }
};

fn getCacheDir(allocator: std.mem.Allocator) ![]const u8 {
    if (std.posix.getenv("XDG_CACHE_HOME")) |xdg| {
        return std.fmt.allocPrint(allocator, "{s}/stl-next/steamgriddb", .{xdg});
    }
    if (std.posix.getenv("HOME")) |home| {
        return std.fmt.allocPrint(allocator, "{s}/.cache/stl-next/steamgriddb", .{home});
    }
    return error.NoCacheDir;
}

fn urlEncode(allocator: std.mem.Allocator, input: []const u8) ![]const u8 {
    var result: std.ArrayList(u8) = .{};
    errdefer result.deinit(allocator);

    for (input) |c| {
        if (std.ascii.isAlphanumeric(c) or c == '-' or c == '_' or c == '.' or c == '~') {
            try result.append(allocator, c);
        } else if (c == ' ') {
            try result.append(allocator, '+');
        } else {
            try result.appendSlice(allocator, &[_]u8{ '%', hexDigit(c >> 4), hexDigit(c & 0x0F) });
        }
    }

    return result.toOwnedSlice(allocator);
}

fn hexDigit(n: u8) u8 {
    const nibble = n & 0x0F;
    return if (nibble < 10) '0' + nibble else 'A' + nibble - 10;
}

fn getMimeExtension(mime: []const u8) []const u8 {
    if (std.mem.eql(u8, mime, "image/png")) return ".png";
    if (std.mem.eql(u8, mime, "image/jpeg")) return ".jpg";
    if (std.mem.eql(u8, mime, "image/webp")) return ".webp";
    if (std.mem.eql(u8, mime, "image/gif")) return ".gif";
    return ".png"; // Default
}

// ═══════════════════════════════════════════════════════════════════════════════
// TESTS
// ═══════════════════════════════════════════════════════════════════════════════

test "url encoding" {
    const allocator = std.testing.allocator;

    const simple = try urlEncode(allocator, "hello");
    defer allocator.free(simple);
    try std.testing.expectEqualStrings("hello", simple);

    const spaces = try urlEncode(allocator, "hello world");
    defer allocator.free(spaces);
    try std.testing.expectEqualStrings("hello+world", spaces);

    const special = try urlEncode(allocator, "Stardew Valley");
    defer allocator.free(special);
    try std.testing.expectEqualStrings("Stardew+Valley", special);
}

test "image type paths" {
    try std.testing.expectEqualStrings("grids", ImageType.grid.toPath());
    try std.testing.expectEqualStrings("heroes", ImageType.hero.toPath());
    try std.testing.expectEqualStrings("logos", ImageType.logo.toPath());
    try std.testing.expectEqualStrings("icons", ImageType.icon.toPath());
}

test "mime extension" {
    try std.testing.expectEqualStrings(".png", getMimeExtension("image/png"));
    try std.testing.expectEqualStrings(".jpg", getMimeExtension("image/jpeg"));
    try std.testing.expectEqualStrings(".webp", getMimeExtension("image/webp"));
}
