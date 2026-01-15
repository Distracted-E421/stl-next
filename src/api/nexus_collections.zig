const std = @import("std");
const json = std.json;

// ═══════════════════════════════════════════════════════════════════════════════
// NEXUS MODS COLLECTIONS API (Phase 7)
// ═══════════════════════════════════════════════════════════════════════════════
//
// Nexus Mods Collections API client for importing mod collections.
// This is separate from the standard Nexus Mods API and uses different endpoints.
//
// Base URL: https://api.nexusmods.com/v2 (GraphQL)
// Alternative: https://next.nexusmods.com/stardewvalley/collections/{slug}
//
// Collections contain:
//   - Metadata (name, author, description)
//   - Mod list with specific file versions
//   - Installation instructions
//   - Revision history
//
// ═══════════════════════════════════════════════════════════════════════════════

pub const CollectionsError = error{
    NoApiKey,
    InvalidApiKey,
    CollectionNotFound,
    RevisionNotFound,
    NetworkError,
    ParseError,
    OutOfMemory,
    RateLimited,
};

/// Collection mod entry
pub const CollectionMod = struct {
    /// Domain name of the mod's game (e.g., "stardewvalley")
    domain_name: []const u8,
    /// Mod ID on Nexus
    mod_id: u32,
    /// Specific file ID (if pinned to a version)
    file_id: ?u32,
    /// Display name
    name: []const u8,
    /// Mod author
    author: ?[]const u8,
    /// Version string
    version: ?[]const u8,
    /// Whether this mod is optional in the collection
    optional: bool,
    /// Category within the collection
    category: ?[]const u8,
    /// Installation instructions/notes
    instructions: ?[]const u8,
    /// Source URL
    source_url: ?[]const u8,

    pub fn deinit(self: *CollectionMod, allocator: std.mem.Allocator) void {
        allocator.free(self.domain_name);
        allocator.free(self.name);
        if (self.author) |a| allocator.free(a);
        if (self.version) |v| allocator.free(v);
        if (self.category) |c| allocator.free(c);
        if (self.instructions) |i| allocator.free(i);
        if (self.source_url) |s| allocator.free(s);
    }
};

/// Collection revision
pub const CollectionRevision = struct {
    revision_number: u32,
    collection_id: u64,
    created_at: i64,
    updated_at: i64,
    /// Status: "published", "draft", "under_moderation"
    status: []const u8,
    /// Changelog for this revision
    changelog: ?[]const u8,

    pub fn deinit(self: *CollectionRevision, allocator: std.mem.Allocator) void {
        allocator.free(self.status);
        if (self.changelog) |c| allocator.free(c);
    }
};

/// Full collection metadata
pub const Collection = struct {
    /// Collection slug (URL identifier)
    slug: []const u8,
    /// Numeric ID
    id: u64,
    /// Display name
    name: []const u8,
    /// Short description/summary
    summary: []const u8,
    /// Full description (HTML)
    description: []const u8,
    /// Author username
    author: []const u8,
    /// Author ID
    author_id: u64,
    /// Game domain (e.g., "stardewvalley")
    game_domain: []const u8,
    /// Total endorsements
    endorsements: u32,
    /// Total downloads
    total_downloads: u64,
    /// Current revision number
    current_revision: u32,
    /// Creation timestamp
    created_at: i64,
    /// Last update timestamp
    updated_at: i64,
    /// Category ID
    category_id: u32,
    /// Header image URL
    header_image: ?[]const u8,
    /// Tile image URL
    tile_image: ?[]const u8,
    /// List of mods in this collection
    mods: []CollectionMod,
    /// Is this an adult-only collection
    adult_content: bool,

    pub fn deinit(self: *Collection, allocator: std.mem.Allocator) void {
        allocator.free(self.slug);
        allocator.free(self.name);
        allocator.free(self.summary);
        allocator.free(self.description);
        allocator.free(self.author);
        allocator.free(self.game_domain);
        if (self.header_image) |h| allocator.free(h);
        if (self.tile_image) |t| allocator.free(t);
        for (self.mods) |*mod| {
            mod.deinit(allocator);
        }
        allocator.free(self.mods);
    }
};

/// Collections API Client
pub const CollectionsClient = struct {
    allocator: std.mem.Allocator,
    api_key: []const u8,

    const Self = @This();
    const BASE_URL = "https://api.nexusmods.com";
    const USER_AGENT = "STL-Next/0.6.1 (Linux; Zig)";

    pub fn init(allocator: std.mem.Allocator, api_key: []const u8) !Self {
        return .{
            .allocator = allocator,
            .api_key = try allocator.dupe(u8, api_key),
        };
    }

    pub fn deinit(self: *Self) void {
        self.allocator.free(self.api_key);
    }

    /// Fetch a collection by slug
    pub fn getCollection(self: *Self, game_domain: []const u8, slug: []const u8, revision: ?u32) !Collection {
        // Build the URL
        // Note: Collections API changed to GraphQL, but we can scrape the JSON from the page
        // Or use the v2 GraphQL endpoint

        const rev_str = if (revision) |r|
            try std.fmt.allocPrint(self.allocator, "{d}", .{r})
        else
            try self.allocator.dupe(u8, "latest");
        defer self.allocator.free(rev_str);

        // Try scraping collection JSON from the web page
        const url = try std.fmt.allocPrint(
            self.allocator,
            "https://next.nexusmods.com/{s}/collections/{s}?tab=about",
            .{ game_domain, slug },
        );
        defer self.allocator.free(url);

        std.log.info("Collections: Fetching {s}", .{url});

        // Use curl to fetch the page and extract collection data
        const collection_json = try self.fetchCollectionJson(game_domain, slug);
        defer self.allocator.free(collection_json);

        return self.parseCollectionJson(collection_json);
    }

    fn fetchCollectionJson(self: *Self, game_domain: []const u8, slug: []const u8) ![]const u8 {
        // Use curl to fetch collection data from Nexus API
        // This uses the GraphQL v2 API

        const query = try std.fmt.allocPrint(
            self.allocator,
            \\{{"query":"query {{\\n  collection(slug: \\"{s}\\") {{\\n    id\\n    slug\\n    name\\n    summary\\n    description\\n    user {{ memberId name }}\\n    game {{ domainName }}\\n    endorsements\\n    totalDownloads\\n    latestRevision {{ revisionNumber }}\\n    createdAt\\n    updatedAt\\n    category {{ id }}\\n    tileImage {{ url }}\\n    headerImage {{ url }}\\n    adultContent\\n    mods {{\\n      mod {{ modId name author version }}\\n      fileId\\n      optional\\n      collectionCategory {{ name }}\\n    }}\\n  }}\\n}}"}}
        ,
            .{slug},
        );
        defer self.allocator.free(query);

        // Write query to temp file for curl
        const temp_file = "/tmp/stl-graphql-query.json";
        {
            const file = try std.fs.createFileAbsolute(temp_file, .{});
            defer file.close();
            try file.writeAll(query);
        }
        defer std.fs.deleteFileAbsolute(temp_file) catch {};

        // Execute curl
        var buf: [256]u8 = undefined;
        const api_header = try std.fmt.bufPrint(&buf, "apikey: {s}", .{self.api_key});

        const argv = [_][]const u8{
            "curl",
            "-X",
            "POST",
            "-H",
            "Content-Type: application/json",
            "-H",
            api_header,
            "-H",
            "User-Agent: " ++ USER_AGENT,
            "-d",
            try std.fmt.allocPrint(self.allocator, "@{s}", .{temp_file}),
            "https://api.nexusmods.com/v2/graphql",
            "--silent",
            "--show-error",
        };
        defer self.allocator.free(argv[10]);

        var child = std.process.Child.init(&argv, self.allocator);
        child.stdout_behavior = .Pipe;
        child.stderr_behavior = .Pipe;

        try child.spawn();

        var stdout: std.ArrayList(u8) = .{};
        defer stdout.deinit(self.allocator);
        var stderr: std.ArrayList(u8) = .{};
        defer stderr.deinit(self.allocator);

        try child.collectOutput(self.allocator, &stdout, &stderr, 1024 * 1024);
        _ = try child.wait();

        _ = game_domain;

        return try stdout.toOwnedSlice(self.allocator);
    }

    fn parseCollectionJson(self: *Self, json_str: []const u8) !Collection {
        var parsed = json.parseFromSlice(json.Value, self.allocator, json_str, .{}) catch {
            return CollectionsError.ParseError;
        };
        defer parsed.deinit();

        const root = parsed.value;
        if (root != .object) return CollectionsError.ParseError;

        // Check for errors
        if (root.object.get("errors")) |_| {
            return CollectionsError.CollectionNotFound;
        }

        const data = root.object.get("data") orelse return CollectionsError.ParseError;
        if (data != .object) return CollectionsError.ParseError;

        const coll = data.object.get("collection") orelse return CollectionsError.CollectionNotFound;
        if (coll != .object) return CollectionsError.ParseError;
        if (coll == .null) return CollectionsError.CollectionNotFound;

        const obj = coll.object;

        // Parse mods array
        var mods_list: std.ArrayList(CollectionMod) = .{};
        errdefer {
            for (mods_list.items) |*m| m.deinit(self.allocator);
            mods_list.deinit(self.allocator);
        }

        if (obj.get("mods")) |mods_arr| {
            if (mods_arr == .array) {
                for (mods_arr.array.items) |mod_item| {
                    if (mod_item != .object) continue;
                    const mod_obj = mod_item.object;

                    var mod = CollectionMod{
                        .domain_name = try self.allocator.dupe(u8, "stardewvalley"),
                        .mod_id = 0,
                        .file_id = null,
                        .name = try self.allocator.dupe(u8, "Unknown"),
                        .author = null,
                        .version = null,
                        .optional = false,
                        .category = null,
                        .instructions = null,
                        .source_url = null,
                    };

                    if (mod_obj.get("mod")) |inner_mod| {
                        if (inner_mod == .object) {
                            const im = inner_mod.object;
                            if (im.get("modId")) |mid| {
                                if (mid == .integer) mod.mod_id = @intCast(mid.integer);
                            }
                            if (im.get("name")) |n| {
                                if (n == .string) {
                                    self.allocator.free(mod.name);
                                    mod.name = try self.allocator.dupe(u8, n.string);
                                }
                            }
                            if (im.get("author")) |a| {
                                if (a == .string) mod.author = try self.allocator.dupe(u8, a.string);
                            }
                            if (im.get("version")) |v| {
                                if (v == .string) mod.version = try self.allocator.dupe(u8, v.string);
                            }
                        }
                    }

                    if (mod_obj.get("fileId")) |fid| {
                        if (fid == .integer) mod.file_id = @intCast(fid.integer);
                    }
                    if (mod_obj.get("optional")) |opt| {
                        if (opt == .bool) mod.optional = opt.bool;
                    }
                    if (mod_obj.get("collectionCategory")) |cat| {
                        if (cat == .object) {
                            if (cat.object.get("name")) |cn| {
                                if (cn == .string) mod.category = try self.allocator.dupe(u8, cn.string);
                            }
                        }
                    }

                    try mods_list.append(self.allocator, mod);
                }
            }
        }

        // Parse main collection fields
        const collection = Collection{
            .slug = try self.allocator.dupe(u8, if (obj.get("slug")) |s| if (s == .string) s.string else "" else ""),
            .id = if (obj.get("id")) |i| if (i == .integer) @intCast(i.integer) else 0 else 0,
            .name = try self.allocator.dupe(u8, if (obj.get("name")) |n| if (n == .string) n.string else "Unknown" else "Unknown"),
            .summary = try self.allocator.dupe(u8, if (obj.get("summary")) |s| if (s == .string) s.string else "" else ""),
            .description = try self.allocator.dupe(u8, if (obj.get("description")) |d| if (d == .string) d.string else "" else ""),
            .author = blk: {
                if (obj.get("user")) |u| {
                    if (u == .object) {
                        if (u.object.get("name")) |n| {
                            if (n == .string) break :blk try self.allocator.dupe(u8, n.string);
                        }
                    }
                }
                break :blk try self.allocator.dupe(u8, "Unknown");
            },
            .author_id = blk: {
                if (obj.get("user")) |u| {
                    if (u == .object) {
                        if (u.object.get("memberId")) |mid| {
                            if (mid == .integer) break :blk @intCast(mid.integer);
                        }
                    }
                }
                break :blk 0;
            },
            .game_domain = blk: {
                if (obj.get("game")) |g| {
                    if (g == .object) {
                        if (g.object.get("domainName")) |dn| {
                            if (dn == .string) break :blk try self.allocator.dupe(u8, dn.string);
                        }
                    }
                }
                break :blk try self.allocator.dupe(u8, "stardewvalley");
            },
            .endorsements = if (obj.get("endorsements")) |e| if (e == .integer) @intCast(e.integer) else 0 else 0,
            .total_downloads = if (obj.get("totalDownloads")) |td| if (td == .integer) @intCast(td.integer) else 0 else 0,
            .current_revision = blk: {
                if (obj.get("latestRevision")) |lr| {
                    if (lr == .object) {
                        if (lr.object.get("revisionNumber")) |rn| {
                            if (rn == .integer) break :blk @intCast(rn.integer);
                        }
                    }
                }
                break :blk 0;
            },
            .created_at = 0,
            .updated_at = 0,
            .category_id = blk: {
                if (obj.get("category")) |c| {
                    if (c == .object) {
                        if (c.object.get("id")) |cid| {
                            if (cid == .integer) break :blk @intCast(cid.integer);
                        }
                    }
                }
                break :blk 0;
            },
            .header_image = blk: {
                if (obj.get("headerImage")) |hi| {
                    if (hi == .object) {
                        if (hi.object.get("url")) |u| {
                            if (u == .string) break :blk try self.allocator.dupe(u8, u.string);
                        }
                    }
                }
                break :blk null;
            },
            .tile_image = blk: {
                if (obj.get("tileImage")) |ti| {
                    if (ti == .object) {
                        if (ti.object.get("url")) |u| {
                            if (u == .string) break :blk try self.allocator.dupe(u8, u.string);
                        }
                    }
                }
                break :blk null;
            },
            .mods = try mods_list.toOwnedSlice(self.allocator),
            .adult_content = if (obj.get("adultContent")) |ac| if (ac == .bool) ac.bool else false else false,
        };

        return collection;
    }

    /// List popular collections for a game
    pub fn listCollections(self: *Self, game_domain: []const u8, limit: u32) ![]Collection {
        _ = self;
        _ = game_domain;
        _ = limit;
        // TODO: Implement using GraphQL query
        return &[_]Collection{};
    }

    /// Search collections
    pub fn searchCollections(self: *Self, game_domain: []const u8, query: []const u8) ![]Collection {
        _ = self;
        _ = game_domain;
        _ = query;
        // TODO: Implement using GraphQL query
        return &[_]Collection{};
    }
};

// ═══════════════════════════════════════════════════════════════════════════════
// TESTS
// ═══════════════════════════════════════════════════════════════════════════════

test "collection mod structure" {
    var mod = CollectionMod{
        .domain_name = try std.testing.allocator.dupe(u8, "stardewvalley"),
        .mod_id = 12345,
        .file_id = 67890,
        .name = try std.testing.allocator.dupe(u8, "Test Mod"),
        .author = try std.testing.allocator.dupe(u8, "TestAuthor"),
        .version = try std.testing.allocator.dupe(u8, "1.0.0"),
        .optional = false,
        .category = null,
        .instructions = null,
        .source_url = null,
    };
    defer mod.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(u32, 12345), mod.mod_id);
    try std.testing.expectEqualStrings("Test Mod", mod.name);
}
