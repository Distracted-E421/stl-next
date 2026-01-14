const std = @import("std");
const vdf = @import("vdf.zig");
const appinfo = @import("appinfo.zig");
const leveldb = @import("leveldb.zig");

// ═══════════════════════════════════════════════════════════════════════════════
// STEAM ENGINE: Steam Installation Discovery & Data Access
// ═══════════════════════════════════════════════════════════════════════════════
//
// Abstracts the complexity of Steam's file layout across different installation
// methods (native, Flatpak, Snap) and provides unified access to:
//
// - Steam installation path
// - Library folders (multiple drives)
// - User data (active user, login state)
// - Game metadata (appinfo.vdf) - FAST via binary streaming
// - User configuration (localconfig.vdf)
// - Collections (LevelDB) - NEW in Phase 2
//
// ═══════════════════════════════════════════════════════════════════════════════

pub const SteamEngine = struct {
    allocator: std.mem.Allocator,
    steam_path: []const u8,
    library_folders: std.ArrayList([]const u8),
    active_user_id: ?u64,
    installation_type: InstallationType,
    collections: ?leveldb.SteamCollections,
    appinfo_cache: ?appinfo.AppInfoParser,

    const Self = @This();

    pub const InstallationType = enum {
        native,
        flatpak,
        snap,
        unknown,
    };

    /// Initialize the Steam Engine by discovering the installation
    pub fn init(allocator: std.mem.Allocator) !Self {
        const steam_path = try discoverSteamPath(allocator);
        const installation_type = detectInstallationType(steam_path);

        var engine = Self{
            .allocator = allocator,
            .steam_path = steam_path,
            .library_folders = std.ArrayList([]const u8).init(allocator),
            .active_user_id = null,
            .installation_type = installation_type,
            .collections = null,
            .appinfo_cache = null,
        };

        // Load library folders
        try engine.loadLibraryFolders();

        // Detect active user
        engine.active_user_id = engine.detectActiveUser() catch null;

        // Initialize collections database
        engine.collections = leveldb.SteamCollections.init(allocator, steam_path) catch null;
        if (engine.collections) |*c| {
            if (engine.active_user_id) |uid| {
                c.setUserId(uid);
            }
        }

        return engine;
    }

    pub fn deinit(self: *Self) void {
        if (self.appinfo_cache) |*cache| cache.deinit();
        if (self.collections) |*c| c.deinit();
        
        self.allocator.free(self.steam_path);
        for (self.library_folders.items) |path| {
            self.allocator.free(path);
        }
        self.library_folders.deinit();
    }

    /// Get information about an installed game using FAST binary VDF parsing
    pub fn getGameInfo(self: *Self, app_id: u32) !GameInfo {
        // Try to get from appinfo.vdf first (fast binary parsing)
        if (try self.getFromAppInfo(app_id)) |info| {
            return info;
        }

        // Fallback: Try to read from appmanifest files
        const game_name = try self.getGameNameFromManifest(app_id);
        const install_dir = try self.getInstallDir(app_id);
        
        return GameInfo{
            .app_id = app_id,
            .name = game_name,
            .install_dir = install_dir,
            .executable = null,
            .proton_version = null,
            .playtime_minutes = 0,
            .is_hidden = self.isGameHidden(app_id),
            .collections = self.getGameCollections(app_id) catch &[_][]const u8{},
        };
    }

    /// Fast lookup using appinfo.vdf binary parser
    fn getFromAppInfo(self: *Self, app_id: u32) !?GameInfo {
        const appinfo_path = try std.fmt.allocPrint(
            self.allocator,
            "{s}/appcache/appinfo.vdf",
            .{self.steam_path},
        );
        defer self.allocator.free(appinfo_path);

        // Check if file exists
        std.fs.accessAbsolute(appinfo_path, .{}) catch return null;

        // Use the fast binary parser
        var parser = try appinfo.AppInfoParser.init(self.allocator, appinfo_path);
        defer parser.deinit();

        // Seek directly to the target AppID
        const entry = try parser.seekToAppId(app_id) orelse return null;
        _ = entry;

        // Parse only this entry's data
        var data = try parser.parseCurrentEntry();
        defer {
            var iter = data.iterator();
            while (iter.next()) |e| {
                freeVdfValue(self.allocator, e.value_ptr);
            }
            data.deinit();
        }

        // Extract high-level info
        const raw_info = try parser.extractGameInfo(app_id, &data);
        
        return GameInfo{
            .app_id = raw_info.app_id,
            .name = raw_info.name,
            .install_dir = raw_info.install_dir,
            .executable = raw_info.executable,
            .proton_version = null,
            .playtime_minutes = 0,
            .is_hidden = self.isGameHidden(app_id),
            .collections = self.getGameCollections(app_id) catch &[_][]const u8{},
        };
    }

    /// Get the game's display name from appmanifest
    fn getGameNameFromManifest(self: *Self, app_id: u32) ![]const u8 {
        for (self.library_folders.items) |lib_path| {
            const manifest_path = try std.fmt.allocPrint(
                self.allocator,
                "{s}/steamapps/appmanifest_{d}.acf",
                .{ lib_path, app_id },
            );
            defer self.allocator.free(manifest_path);

            const file = std.fs.openFileAbsolute(manifest_path, .{}) catch continue;
            defer file.close();

            // Read and parse the manifest
            const stat = try file.stat();
            const content = try self.allocator.alloc(u8, stat.size);
            defer self.allocator.free(content);
            _ = try file.readAll(content);

            var parser = vdf.TextParser.init(self.allocator, content);
            var result = parser.parse() catch continue;
            defer result.deinit();

            // Look for "AppState" -> "name"
            if (result.get("AppState")) |app_state| {
                switch (app_state) {
                    .map => |m| {
                        if (m.get("name")) |name_val| {
                            switch (name_val) {
                                .string => |s| return try self.allocator.dupe(u8, s),
                                else => {},
                            }
                        }
                    },
                    else => {},
                }
            }
        }

        // Fallback to generic name
        return try std.fmt.allocPrint(self.allocator, "Game {d}", .{app_id});
    }

    /// Get the installation directory for a game
    fn getInstallDir(self: *Self, app_id: u32) ![]const u8 {
        for (self.library_folders.items) |lib_path| {
            const manifest_path = try std.fmt.allocPrint(
                self.allocator,
                "{s}/steamapps/appmanifest_{d}.acf",
                .{ lib_path, app_id },
            );
            defer self.allocator.free(manifest_path);

            const file = std.fs.openFileAbsolute(manifest_path, .{}) catch continue;
            defer file.close();

            const stat = try file.stat();
            const content = try self.allocator.alloc(u8, stat.size);
            defer self.allocator.free(content);
            _ = try file.readAll(content);

            var parser = vdf.TextParser.init(self.allocator, content);
            var result = parser.parse() catch continue;
            defer result.deinit();

            if (result.get("AppState")) |app_state| {
                switch (app_state) {
                    .map => |m| {
                        if (m.get("installdir")) |dir_val| {
                            switch (dir_val) {
                                .string => |s| {
                                    return try std.fmt.allocPrint(
                                        self.allocator,
                                        "{s}/steamapps/common/{s}",
                                        .{ lib_path, s },
                                    );
                                },
                                else => {},
                            }
                        }
                    },
                    else => {},
                }
            }
        }

        return try self.allocator.dupe(u8, "");
    }

    /// Check if a game is hidden via LevelDB collections
    pub fn isGameHidden(self: *Self, app_id: u32) bool {
        var collections = self.collections orelse return false;
        return collections.isHidden(app_id);
    }

    /// Get collections/tags for a game
    pub fn getGameCollections(self: *Self, app_id: u32) ![]const []const u8 {
        var collections = self.collections orelse return &[_][]const u8{};
        return collections.getGameCollections(app_id);
    }

    /// Get all games in a specific collection
    pub fn getGamesInCollection(self: *Self, collection_name: []const u8) ![]u32 {
        var collections = self.collections orelse return &[_]u32{};
        return collections.getGamesInCollection(collection_name);
    }

    /// List all installed games (fast enumeration)
    pub fn listInstalledGames(self: *Self) ![]GameInfo {
        var games = std.ArrayList(GameInfo).init(self.allocator);
        errdefer games.deinit();

        for (self.library_folders.items) |lib_path| {
            const steamapps_path = try std.fmt.allocPrint(
                self.allocator,
                "{s}/steamapps",
                .{lib_path},
            );
            defer self.allocator.free(steamapps_path);

            var dir = std.fs.openDirAbsolute(steamapps_path, .{ .iterate = true }) catch continue;
            defer dir.close();

            var iter = dir.iterate();
            while (try iter.next()) |entry| {
                if (std.mem.startsWith(u8, entry.name, "appmanifest_") and
                    std.mem.endsWith(u8, entry.name, ".acf"))
                {
                    // Extract AppID from filename
                    const id_start = "appmanifest_".len;
                    const id_end = entry.name.len - ".acf".len;
                    const id_str = entry.name[id_start..id_end];

                    if (std.fmt.parseInt(u32, id_str, 10)) |app_id| {
                        // Skip hidden games
                        if (self.isGameHidden(app_id)) continue;
                        
                        const info = self.getGameInfo(app_id) catch continue;
                        try games.append(info);
                    } else |_| {}
                }
            }
        }

        return games.toOwnedSlice();
    }

    /// List available Proton versions
    pub fn listProtonVersions(self: *Self) ![]ProtonInfo {
        var protons = std.ArrayList(ProtonInfo).init(self.allocator);
        errdefer protons.deinit();

        // Check Steam's compatibility tools directory
        const compat_path = try std.fmt.allocPrint(
            self.allocator,
            "{s}/compatibilitytools.d",
            .{self.steam_path},
        );
        defer self.allocator.free(compat_path);

        var dir = std.fs.openDirAbsolute(compat_path, .{ .iterate = true }) catch {
            return protons.toOwnedSlice();
        };
        defer dir.close();

        var iter = dir.iterate();
        while (try iter.next()) |entry| {
            if (entry.kind == .directory) {
                // Check if it's a valid Proton/Wine installation
                const tool_path = try std.fmt.allocPrint(
                    self.allocator,
                    "{s}/{s}",
                    .{ compat_path, entry.name },
                );

                // Look for toolmanifest.vdf to verify it's a compat tool
                const manifest_path = try std.fmt.allocPrint(
                    self.allocator,
                    "{s}/toolmanifest.vdf",
                    .{tool_path},
                );
                defer self.allocator.free(manifest_path);

                std.fs.accessAbsolute(manifest_path, .{}) catch {
                    self.allocator.free(tool_path);
                    continue;
                };

                try protons.append(.{
                    .name = try self.allocator.dupe(u8, entry.name),
                    .path = tool_path,
                    .is_proton = std.mem.indexOf(u8, entry.name, "Proton") != null or
                                 std.mem.indexOf(u8, entry.name, "proton") != null,
                });
            }
        }

        // Also check Steam's internal Proton tools
        for (self.library_folders.items) |lib_path| {
            const proton_path = try std.fmt.allocPrint(
                self.allocator,
                "{s}/steamapps/common",
                .{lib_path},
            );
            defer self.allocator.free(proton_path);

            var common_dir = std.fs.openDirAbsolute(proton_path, .{ .iterate = true }) catch continue;
            defer common_dir.close();

            var common_iter = common_dir.iterate();
            while (try common_iter.next()) |entry| {
                if (entry.kind == .directory and 
                    (std.mem.startsWith(u8, entry.name, "Proton") or
                     std.mem.startsWith(u8, entry.name, "SteamLinuxRuntime"))) 
                {
                    const tool_path = try std.fmt.allocPrint(
                        self.allocator,
                        "{s}/{s}",
                        .{ proton_path, entry.name },
                    );

                    try protons.append(.{
                        .name = try self.allocator.dupe(u8, entry.name),
                        .path = tool_path,
                        .is_proton = std.mem.startsWith(u8, entry.name, "Proton"),
                    });
                }
            }
        }

        return protons.toOwnedSlice();
    }

    /// Load library folders from libraryfolders.vdf
    fn loadLibraryFolders(self: *Self) !void {
        const lib_vdf_path = try std.fmt.allocPrint(
            self.allocator,
            "{s}/steamapps/libraryfolders.vdf",
            .{self.steam_path},
        );
        defer self.allocator.free(lib_vdf_path);

        // Always add the main Steam path
        try self.library_folders.append(try self.allocator.dupe(u8, self.steam_path));

        // Parse libraryfolders.vdf for additional libraries
        const file = std.fs.openFileAbsolute(lib_vdf_path, .{}) catch return;
        defer file.close();

        const stat = try file.stat();
        const content = try self.allocator.alloc(u8, stat.size);
        defer self.allocator.free(content);
        _ = try file.readAll(content);

        var parser = vdf.TextParser.init(self.allocator, content);
        var result = parser.parse() catch return;
        defer result.deinit();

        // The structure is: "libraryfolders" { "0" { "path" "..." } "1" { ... } }
        if (result.get("libraryfolders")) |lf| {
            switch (lf) {
                .map => |m| {
                    var iter = m.iterator();
                    while (iter.next()) |entry| {
                        // Skip non-numeric keys
                        _ = std.fmt.parseInt(u32, entry.key_ptr.*, 10) catch continue;

                        switch (entry.value_ptr.*) {
                            .map => |lib_map| {
                                if (lib_map.get("path")) |path_val| {
                                    switch (path_val) {
                                        .string => |path| {
                                            // Don't add duplicates
                                            var found = false;
                                            for (self.library_folders.items) |existing| {
                                                if (std.mem.eql(u8, existing, path)) {
                                                    found = true;
                                                    break;
                                                }
                                            }
                                            if (!found) {
                                                try self.library_folders.append(
                                                    try self.allocator.dupe(u8, path),
                                                );
                                            }
                                        },
                                        else => {},
                                    }
                                }
                            },
                            else => {},
                        }
                    }
                },
                else => {},
            }
        }
    }

    /// Detect the active Steam user from loginusers.vdf
    fn detectActiveUser(self: *Self) !?u64 {
        const login_path = try std.fmt.allocPrint(
            self.allocator,
            "{s}/config/loginusers.vdf",
            .{self.steam_path},
        );
        defer self.allocator.free(login_path);

        const file = std.fs.openFileAbsolute(login_path, .{}) catch return null;
        defer file.close();

        const stat = try file.stat();
        const content = try self.allocator.alloc(u8, stat.size);
        defer self.allocator.free(content);
        _ = try file.readAll(content);

        var parser = vdf.TextParser.init(self.allocator, content);
        var result = parser.parse() catch return null;
        defer result.deinit();

        // Look for the user with "MostRecent" = "1"
        if (result.get("users")) |users| {
            switch (users) {
                .map => |m| {
                    var iter = m.iterator();
                    while (iter.next()) |entry| {
                        const steam_id = std.fmt.parseInt(u64, entry.key_ptr.*, 10) catch continue;

                        switch (entry.value_ptr.*) {
                            .map => |user_map| {
                                if (user_map.get("MostRecent")) |recent| {
                                    switch (recent) {
                                        .string => |s| {
                                            if (std.mem.eql(u8, s, "1")) {
                                                return steam_id;
                                            }
                                        },
                                        else => {},
                                    }
                                }
                            },
                            else => {},
                        }
                    }
                },
                else => {},
            }
        }

        return null;
    }
    
    /// Get the compatdata (Wine prefix) path for a game
    pub fn getCompatDataPath(self: *Self, app_id: u32) !?[]const u8 {
        for (self.library_folders.items) |lib_path| {
            const compat_path = try std.fmt.allocPrint(
                self.allocator,
                "{s}/steamapps/compatdata/{d}",
                .{ lib_path, app_id },
            );
            
            std.fs.accessAbsolute(compat_path, .{}) catch {
                self.allocator.free(compat_path);
                continue;
            };
            
            return compat_path;
        }
        
        return null;
    }
    
    /// Get user-specific launch options from localconfig.vdf
    pub fn getUserLaunchOptions(self: *Self, app_id: u32) !?[]const u8 {
        const user_id = self.active_user_id orelse return null;
        
        const config_path = try std.fmt.allocPrint(
            self.allocator,
            "{s}/userdata/{d}/config/localconfig.vdf",
            .{ self.steam_path, user_id },
        );
        defer self.allocator.free(config_path);
        
        const file = std.fs.openFileAbsolute(config_path, .{}) catch return null;
        defer file.close();
        
        const stat = try file.stat();
        const content = try self.allocator.alloc(u8, stat.size);
        defer self.allocator.free(content);
        _ = try file.readAll(content);
        
        var parser = vdf.TextParser.init(self.allocator, content);
        var result = parser.parse() catch return null;
        defer result.deinit();
        
        // Navigate: UserLocalConfigStore/Software/Valve/Steam/Apps/<appid>/LaunchOptions
        const path = try std.fmt.allocPrint(
            self.allocator,
            "UserLocalConfigStore/Software/Valve/Steam/Apps/{d}/LaunchOptions",
            .{app_id},
        );
        defer self.allocator.free(path);
        
        if (vdf.getByPath(&result, path)) |value| {
            switch (value.*) {
                .string => |s| return try self.allocator.dupe(u8, s),
                else => {},
            }
        }
        
        return null;
    }
};

/// Discover the Steam installation path
fn discoverSteamPath(allocator: std.mem.Allocator) ![]const u8 {
    const home = std.posix.getenv("HOME") orelse return error.NoHomeDirectory;

    // Check paths in order of preference
    const paths = [_][]const u8{
        // Native Steam
        "/.steam/steam",
        "/.local/share/Steam",
        // Flatpak
        "/.var/app/com.valvesoftware.Steam/data/Steam",
        // Snap
        "/snap/steam/common/.steam/steam",
    };

    for (paths) |suffix| {
        const path = try std.fmt.allocPrint(allocator, "{s}{s}", .{ home, suffix });

        // Check if steam.sh exists (definitive marker)
        const steam_sh = try std.fmt.allocPrint(allocator, "{s}/steam.sh", .{path});
        defer allocator.free(steam_sh);

        std.fs.accessAbsolute(steam_sh, .{}) catch {
            allocator.free(path);
            continue;
        };

        return path;
    }

    return error.SteamNotFound;
}

/// Detect the installation type from the path
fn detectInstallationType(path: []const u8) SteamEngine.InstallationType {
    if (std.mem.indexOf(u8, path, ".var/app/com.valvesoftware.Steam")) |_| {
        return .flatpak;
    } else if (std.mem.indexOf(u8, path, "/snap/")) |_| {
        return .snap;
    } else if (std.mem.indexOf(u8, path, "/.steam/") != null or
        std.mem.indexOf(u8, path, "/.local/share/Steam") != null)
    {
        return .native;
    }
    return .unknown;
}

fn freeVdfValue(allocator: std.mem.Allocator, value: *vdf.Value) void {
    switch (value.*) {
        .string => |s| allocator.free(s),
        .map => |*m| {
            var iter = m.iterator();
            while (iter.next()) |e| {
                allocator.free(e.key_ptr.*);
                freeVdfValue(allocator, e.value_ptr);
            }
            m.deinit();
        },
        else => {},
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// DATA TYPES
// ═══════════════════════════════════════════════════════════════════════════════

pub const GameInfo = struct {
    app_id: u32,
    name: []const u8,
    install_dir: []const u8,
    executable: ?[]const u8,
    proton_version: ?[]const u8,
    playtime_minutes: u32,
    is_hidden: bool,
    collections: []const []const u8,
};

pub const ProtonInfo = struct {
    name: []const u8,
    path: []const u8,
    is_proton: bool,
};

// ═══════════════════════════════════════════════════════════════════════════════
// TESTS
// ═══════════════════════════════════════════════════════════════════════════════

test "detect installation type" {
    try std.testing.expectEqual(
        SteamEngine.InstallationType.native,
        detectInstallationType("/home/user/.steam/steam"),
    );
    try std.testing.expectEqual(
        SteamEngine.InstallationType.flatpak,
        detectInstallationType("/home/user/.var/app/com.valvesoftware.Steam/data/Steam"),
    );
}
