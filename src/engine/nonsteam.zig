const std = @import("std");
const fs = std.fs;
const json = std.json;

// ═══════════════════════════════════════════════════════════════════════════════
// NON-STEAM GAMES
// ═══════════════════════════════════════════════════════════════════════════════
//
// Manages non-Steam games including:
//   - Native Linux games (AppImage, binaries)
//   - Windows games via Wine/Proton
//   - GOG, Epic, and other store games
//
// Non-Steam games get negative AppIDs (starting from -1000) to avoid conflicts.
// They can use all the same features as Steam games:
//   - MangoHud, Gamescope, GameMode
//   - Custom commands
//   - Winetricks
//   - SteamGridDB artwork
//
// ═══════════════════════════════════════════════════════════════════════════════

/// Platform types for non-Steam games
pub const Platform = enum {
    /// Native Linux binary
    native,
    /// Windows game requiring Wine/Proton
    windows,
    /// Flatpak application
    flatpak,
    /// AppImage
    appimage,
    /// Snap package
    snap,
    /// Browser game (URL)
    web,
};

/// Source store for the game
pub const GameSource = enum {
    /// Manually added
    manual,
    /// GOG Galaxy
    gog,
    /// Epic Games Store (via Heroic/Legendary)
    epic,
    /// Amazon Prime Gaming
    amazon,
    /// EA Origin/EA App
    ea,
    /// Ubisoft Connect
    ubisoft,
    /// itch.io
    itch,
    /// Humble Bundle
    humble,
    /// Game Jolt
    gamejolt,
};

/// Non-Steam game entry
pub const NonSteamGame = struct {
    /// Internal ID (negative to avoid Steam AppID collision)
    id: i32,
    
    /// Display name
    name: []const u8,
    
    /// Platform type
    platform: Platform,
    
    /// Source store
    source: GameSource = .manual,
    
    /// Path to executable
    executable: []const u8,
    
    /// Working directory (null = executable's directory)
    working_dir: ?[]const u8 = null,
    
    /// Launch arguments
    arguments: []const u8 = "",
    
    /// For Windows games: Wine prefix path (null = create one)
    prefix_path: ?[]const u8 = null,
    
    /// For Windows games: specific Proton/Wine version
    proton_version: ?[]const u8 = null,
    
    /// Path to game icon (for SteamGridDB lookup)
    icon_path: ?[]const u8 = null,
    
    /// SteamGridDB game ID (for artwork)
    steamgriddb_id: ?u32 = null,
    
    /// IGDB game ID (for metadata)
    igdb_id: ?u32 = null,
    
    /// Tags/categories
    tags: []const []const u8 = &.{},
    
    /// Total playtime in minutes
    playtime_minutes: u32 = 0,
    
    /// Last played timestamp (Unix epoch)
    last_played: ?i64 = null,
    
    /// Hidden from main list
    hidden: bool = false,
    
    /// Custom environment variables
    env_vars: []const EnvVar = &.{},
    
    /// Notes (user comments)
    notes: []const u8 = "",

    pub fn deinit(self: *NonSteamGame, allocator: std.mem.Allocator) void {
        allocator.free(self.name);
        allocator.free(self.executable);
        if (self.working_dir) |w| allocator.free(w);
        if (self.prefix_path) |p| allocator.free(p);
        if (self.proton_version) |v| allocator.free(v);
        if (self.icon_path) |i| allocator.free(i);
        for (self.tags) |t| allocator.free(t);
        if (self.tags.len > 0) allocator.free(self.tags);
        // EnvVar cleanup - use non-mutating free since we don't need to modify
        for (self.env_vars) |e| {
            allocator.free(e.key);
            allocator.free(e.value);
        }
        if (self.env_vars.len > 0) allocator.free(self.env_vars);
        if (self.notes.len > 0) allocator.free(self.notes);
    }
};

/// Custom environment variable
pub const EnvVar = struct {
    key: []const u8,
    value: []const u8,

    pub fn deinit(self: *EnvVar, allocator: std.mem.Allocator) void {
        allocator.free(self.key);
        allocator.free(self.value);
    }
};

/// Non-Steam game manager
pub const NonSteamManager = struct {
    allocator: std.mem.Allocator,
    config_dir: []const u8,
    games: std.ArrayList(NonSteamGame),
    next_id: i32,

    const Self = @This();
    
    /// Starting ID for non-Steam games (negative to avoid collision)
    const START_ID: i32 = -1000;

    pub fn init(allocator: std.mem.Allocator) !Self {
        const config_dir = try getConfigDir(allocator);
        
        var manager = Self{
            .allocator = allocator,
            .config_dir = config_dir,
            .games = .{},
            .next_id = START_ID,
        };
        
        try manager.load();
        
        return manager;
    }

    pub fn deinit(self: *Self) void {
        for (self.games.items) |*game| {
            game.deinit(self.allocator);
        }
        self.games.deinit(self.allocator);
        self.allocator.free(self.config_dir);
    }

    /// Add a new non-Steam game
    pub fn addGame(self: *Self, game: NonSteamGame) !void {
        var new_game = game;
        new_game.id = self.next_id;
        self.next_id -= 1;
        
        try self.games.append(self.allocator, new_game);
        try self.save();
        
        std.log.info("NonSteam: Added game '{s}' (ID: {d})", .{ game.name, new_game.id });
    }

    /// Remove a game by ID
    pub fn removeGame(self: *Self, id: i32) !void {
        for (self.games.items, 0..) |*game, i| {
            if (game.id == id) {
                const name = game.name;
                game.deinit(self.allocator);
                _ = self.games.orderedRemove(i);
                try self.save();
                std.log.info("NonSteam: Removed game '{s}'", .{name});
                return;
            }
        }
        return error.GameNotFound;
    }

    /// Get a game by ID
    pub fn getGame(self: *Self, id: i32) ?*NonSteamGame {
        for (self.games.items) |*game| {
            if (game.id == id) return game;
        }
        return null;
    }

    /// List all games
    pub fn listGames(self: *Self) []NonSteamGame {
        return self.games.items;
    }

    /// List visible games (not hidden)
    pub fn listVisibleGames(self: *Self) ![]NonSteamGame {
        var visible: std.ArrayList(NonSteamGame) = .{};
        for (self.games.items) |game| {
            if (!game.hidden) {
                try visible.append(self.allocator, game);
            }
        }
        return visible.toOwnedSlice(self.allocator);
    }

    /// Import games from GOG Galaxy
    pub fn importFromGog(self: *Self, gog_path: []const u8) !usize {
        _ = self;
        _ = gog_path;
        // TODO: Parse GOG Galaxy database
        return error.NotImplemented;
    }

    /// Import games from Heroic (Epic/GOG/Amazon)
    pub fn importFromHeroic(self: *Self) !usize {
        const heroic_config = try std.fmt.allocPrint(
            self.allocator,
            "{s}/.config/heroic",
            .{std.posix.getenv("HOME") orelse "/home"},
        );
        defer self.allocator.free(heroic_config);
        
        var count: usize = 0;
        
        // Try Epic games
        const epic_library = try std.fmt.allocPrint(
            self.allocator,
            "{s}/lib-cache/library.json",
            .{heroic_config},
        );
        defer self.allocator.free(epic_library);
        
        count += self.parseHeroicLibrary(epic_library, .epic) catch 0;
        
        // Try GOG games
        const gog_library = try std.fmt.allocPrint(
            self.allocator,
            "{s}/gog_store/library.json",
            .{heroic_config},
        );
        defer self.allocator.free(gog_library);
        
        count += self.parseHeroicLibrary(gog_library, .gog) catch 0;
        
        if (count > 0) {
            try self.save();
        }
        
        return count;
    }

    fn parseHeroicLibrary(self: *Self, path: []const u8, source: GameSource) !usize {
        const file = fs.openFileAbsolute(path, .{}) catch return 0;
        defer file.close();
        
        const stat = try file.stat();
        const content = try self.allocator.alloc(u8, stat.size);
        defer self.allocator.free(content);
        _ = try file.readAll(content);
        
        var parsed = json.parseFromSlice(json.Value, self.allocator, content, .{}) catch return 0;
        defer parsed.deinit();
        
        if (parsed.value != .object) return 0;
        
        var count: usize = 0;
        
        // Parse library structure
        if (parsed.value.object.get("library")) |library| {
            if (library == .array) {
                for (library.array.items) |item| {
                    if (item != .object) continue;
                    const obj = item.object;
                    
                    const title = obj.get("title") orelse continue;
                    if (title != .string) continue;
                    
                    const install_path = obj.get("install_path") orelse continue;
                    if (install_path != .string) continue;
                    
                    // Find executable
                    const exe = obj.get("executable") orelse continue;
                    if (exe != .string) continue;
                    
                    const game = NonSteamGame{
                        .id = 0, // Will be assigned
                        .name = try self.allocator.dupe(u8, title.string),
                        .platform = .windows,
                        .source = source,
                        .executable = try self.allocator.dupe(u8, exe.string),
                        .working_dir = try self.allocator.dupe(u8, install_path.string),
                    };
                    
                    try self.addGame(game);
                    count += 1;
                }
            }
        }
        
        return count;
    }

    /// Load games from disk
    fn load(self: *Self) !void {
        const games_file = try std.fmt.allocPrint(
            self.allocator,
            "{s}/nonsteam.json",
            .{self.config_dir},
        );
        defer self.allocator.free(games_file);
        
        const file = fs.openFileAbsolute(games_file, .{}) catch |err| {
            if (err == error.FileNotFound) {
                std.log.debug("NonSteam: No saved games found", .{});
                return;
            }
            return err;
        };
        defer file.close();
        
        const stat = try file.stat();
        const content = try self.allocator.alloc(u8, stat.size);
        defer self.allocator.free(content);
        _ = try file.readAll(content);
        
        var parsed = json.parseFromSlice(json.Value, self.allocator, content, .{}) catch |err| {
            std.log.warn("NonSteam: Failed to parse saved games: {}", .{err});
            return;
        };
        defer parsed.deinit();
        
        if (parsed.value != .object) return;
        
        // Parse next_id
        if (parsed.value.object.get("next_id")) |id| {
            if (id == .integer) {
                self.next_id = @intCast(id.integer);
            }
        }
        
        // Parse games array
        if (parsed.value.object.get("games")) |games_arr| {
            if (games_arr == .array) {
                for (games_arr.array.items) |item| {
                    if (self.parseGameEntry(item)) |game| {
                        try self.games.append(self.allocator, game);
                    }
                }
            }
        }
        
        std.log.info("NonSteam: Loaded {d} game(s)", .{self.games.items.len});
    }

    fn parseGameEntry(self: *Self, value: json.Value) ?NonSteamGame {
        if (value != .object) return null;
        const obj = value.object;
        
        const id = obj.get("id") orelse return null;
        if (id != .integer) return null;
        
        const name = obj.get("name") orelse return null;
        if (name != .string) return null;
        
        const executable = obj.get("executable") orelse return null;
        if (executable != .string) return null;
        
        const platform_str = obj.get("platform") orelse return null;
        if (platform_str != .string) return null;
        const platform = std.meta.stringToEnum(Platform, platform_str.string) orelse return null;
        
        var game = NonSteamGame{
            .id = @intCast(id.integer),
            .name = self.allocator.dupe(u8, name.string) catch return null,
            .platform = platform,
            .executable = self.allocator.dupe(u8, executable.string) catch return null,
        };
        
        // Optional fields
        if (obj.get("source")) |v| {
            if (v == .string) {
                game.source = std.meta.stringToEnum(GameSource, v.string) orelse .manual;
            }
        }
        if (obj.get("working_dir")) |v| {
            if (v == .string) game.working_dir = self.allocator.dupe(u8, v.string) catch null;
        }
        if (obj.get("arguments")) |v| {
            if (v == .string) game.arguments = self.allocator.dupe(u8, v.string) catch "";
        }
        if (obj.get("prefix_path")) |v| {
            if (v == .string) game.prefix_path = self.allocator.dupe(u8, v.string) catch null;
        }
        if (obj.get("proton_version")) |v| {
            if (v == .string) game.proton_version = self.allocator.dupe(u8, v.string) catch null;
        }
        if (obj.get("steamgriddb_id")) |v| {
            if (v == .integer) game.steamgriddb_id = @intCast(v.integer);
        }
        if (obj.get("playtime_minutes")) |v| {
            if (v == .integer) game.playtime_minutes = @intCast(v.integer);
        }
        if (obj.get("hidden")) |v| {
            if (v == .bool) game.hidden = v.bool;
        }
        if (obj.get("notes")) |v| {
            if (v == .string) game.notes = self.allocator.dupe(u8, v.string) catch "";
        }
        
        return game;
    }

    /// Save games to disk
    fn save(self: *Self) !void {
        // Ensure config dir exists
        fs.makeDirAbsolute(self.config_dir) catch |err| {
            if (err != error.PathAlreadyExists) return err;
        };
        
        const games_file = try std.fmt.allocPrint(
            self.allocator,
            "{s}/nonsteam.json",
            .{self.config_dir},
        );
        defer self.allocator.free(games_file);
        
        const file = try fs.createFileAbsolute(games_file, .{});
        defer file.close();
        
        // Zig 0.15.x: Use direct file.writeAll() with allocPrint for formatting
        try file.writeAll("{\n");
        
        const next_id_line = try std.fmt.allocPrint(self.allocator, "  \"next_id\": {d},\n", .{self.next_id});
        defer self.allocator.free(next_id_line);
        try file.writeAll(next_id_line);
        
        try file.writeAll("  \"games\": [\n");
        
        for (self.games.items, 0..) |game, i| {
            try file.writeAll("    {\n");
            
            const id_line = try std.fmt.allocPrint(self.allocator, "      \"id\": {d},\n", .{game.id});
            defer self.allocator.free(id_line);
            try file.writeAll(id_line);
            
            const name_line = try std.fmt.allocPrint(self.allocator, "      \"name\": \"{s}\",\n", .{game.name});
            defer self.allocator.free(name_line);
            try file.writeAll(name_line);
            
            const platform_line = try std.fmt.allocPrint(self.allocator, "      \"platform\": \"{s}\",\n", .{@tagName(game.platform)});
            defer self.allocator.free(platform_line);
            try file.writeAll(platform_line);
            
            const source_line = try std.fmt.allocPrint(self.allocator, "      \"source\": \"{s}\",\n", .{@tagName(game.source)});
            defer self.allocator.free(source_line);
            try file.writeAll(source_line);
            
            const exec_line = try std.fmt.allocPrint(self.allocator, "      \"executable\": \"{s}\",\n", .{game.executable});
            defer self.allocator.free(exec_line);
            try file.writeAll(exec_line);
            
            if (game.working_dir) |w| {
                const wd_line = try std.fmt.allocPrint(self.allocator, "      \"working_dir\": \"{s}\",\n", .{w});
                defer self.allocator.free(wd_line);
                try file.writeAll(wd_line);
            }
            if (game.arguments.len > 0) {
                const args_line = try std.fmt.allocPrint(self.allocator, "      \"arguments\": \"{s}\",\n", .{game.arguments});
                defer self.allocator.free(args_line);
                try file.writeAll(args_line);
            }
            if (game.prefix_path) |p| {
                const prefix_line = try std.fmt.allocPrint(self.allocator, "      \"prefix_path\": \"{s}\",\n", .{p});
                defer self.allocator.free(prefix_line);
                try file.writeAll(prefix_line);
            }
            if (game.proton_version) |v| {
                const proton_line = try std.fmt.allocPrint(self.allocator, "      \"proton_version\": \"{s}\",\n", .{v});
                defer self.allocator.free(proton_line);
                try file.writeAll(proton_line);
            }
            if (game.steamgriddb_id) |id| {
                const sgdb_line = try std.fmt.allocPrint(self.allocator, "      \"steamgriddb_id\": {d},\n", .{id});
                defer self.allocator.free(sgdb_line);
                try file.writeAll(sgdb_line);
            }
            
            const playtime_line = try std.fmt.allocPrint(self.allocator, "      \"playtime_minutes\": {d},\n", .{game.playtime_minutes});
            defer self.allocator.free(playtime_line);
            try file.writeAll(playtime_line);
            
            const hidden_line = try std.fmt.allocPrint(self.allocator, "      \"hidden\": {s},\n", .{if (game.hidden) "true" else "false"});
            defer self.allocator.free(hidden_line);
            try file.writeAll(hidden_line);
            
            if (game.notes.len > 0) {
                const notes_line = try std.fmt.allocPrint(self.allocator, "      \"notes\": \"{s}\"\n", .{game.notes});
                defer self.allocator.free(notes_line);
                try file.writeAll(notes_line);
            } else {
                try file.writeAll("      \"notes\": \"\"\n");
            }
            
            try file.writeAll("    }");
            if (i < self.games.items.len - 1) {
                try file.writeAll(",");
            }
            try file.writeAll("\n");
        }
        
        try file.writeAll("  ]\n");
        try file.writeAll("}\n");
        
        std.log.debug("NonSteam: Saved {d} game(s)", .{self.games.items.len});
    }
};

fn getConfigDir(allocator: std.mem.Allocator) ![]const u8 {
    if (std.posix.getenv("STL_CONFIG_DIR")) |dir| {
        return allocator.dupe(u8, dir);
    }
    if (std.posix.getenv("XDG_CONFIG_HOME")) |xdg| {
        return std.fmt.allocPrint(allocator, "{s}/stl-next", .{xdg});
    }
    if (std.posix.getenv("HOME")) |home| {
        return std.fmt.allocPrint(allocator, "{s}/.config/stl-next", .{home});
    }
    return error.NoConfigDir;
}

// ═══════════════════════════════════════════════════════════════════════════════
// QUICK ADD HELPERS
// ═══════════════════════════════════════════════════════════════════════════════

/// Quick add a native Linux game
pub fn addNativeGame(
    manager: *NonSteamManager,
    name: []const u8,
    executable: []const u8,
) !void {
    const game = NonSteamGame{
        .id = 0,
        .name = try manager.allocator.dupe(u8, name),
        .platform = .native,
        .executable = try manager.allocator.dupe(u8, executable),
    };
    try manager.addGame(game);
}

/// Quick add a Windows game
pub fn addWindowsGame(
    manager: *NonSteamManager,
    name: []const u8,
    executable: []const u8,
    proton_version: ?[]const u8,
) !void {
    const game = NonSteamGame{
        .id = 0,
        .name = try manager.allocator.dupe(u8, name),
        .platform = .windows,
        .executable = try manager.allocator.dupe(u8, executable),
        .proton_version = if (proton_version) |v| try manager.allocator.dupe(u8, v) else null,
    };
    try manager.addGame(game);
}

// ═══════════════════════════════════════════════════════════════════════════════
// TESTS
// ═══════════════════════════════════════════════════════════════════════════════

test "platform enum" {
    try std.testing.expectEqual(Platform.native, std.meta.stringToEnum(Platform, "native").?);
    try std.testing.expectEqual(Platform.windows, std.meta.stringToEnum(Platform, "windows").?);
}

test "source enum" {
    try std.testing.expectEqual(GameSource.gog, std.meta.stringToEnum(GameSource, "gog").?);
    try std.testing.expectEqual(GameSource.epic, std.meta.stringToEnum(GameSource, "epic").?);
}

