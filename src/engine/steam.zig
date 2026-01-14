const std = @import("std");
const vdf = @import("vdf.zig");

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
// - Game metadata (appinfo.vdf)
// - User configuration (localconfig.vdf)
// - Collections (LevelDB)
//
// ═══════════════════════════════════════════════════════════════════════════════

pub const SteamEngine = struct {
    allocator: std.mem.Allocator,
    steam_path: []const u8,
    library_folders: std.ArrayList([]const u8),
    active_user_id: ?u64,
    installation_type: InstallationType,

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
        };

        // Load library folders
        try engine.loadLibraryFolders();

        // Detect active user
        engine.active_user_id = try engine.detectActiveUser();

        return engine;
    }

    pub fn deinit(self: *Self) void {
        self.allocator.free(self.steam_path);
        for (self.library_folders.items) |path| {
            self.allocator.free(path);
        }
        self.library_folders.deinit();
    }

    /// Get information about an installed game
    pub fn getGameInfo(self: *const Self, app_id: u32) !GameInfo {
        // First, try to find in appinfo.vdf (binary, fast)
        const appinfo_path = try std.fmt.allocPrint(
            self.allocator,
            "{s}/appcache/appinfo.vdf",
            .{self.steam_path},
        );
        defer self.allocator.free(appinfo_path);

        // Check if appinfo.vdf exists
        std.fs.accessAbsolute(appinfo_path, .{}) catch {
            return error.AppInfoNotFound;
        };

        // For now, return stub data - full implementation parses binary VDF
        // This is where the streaming parser from vdf.zig would be used

        // Check localconfig for user-specific data
        const game_name = try self.getGameName(app_id);

        return GameInfo{
            .app_id = app_id,
            .name = game_name,
            .install_dir = "TODO",
            .executable = "TODO",
            .proton_version = null,
            .playtime_minutes = 0,
        };
    }

    /// Get the game's display name
    fn getGameName(self: *const Self, app_id: u32) ![]const u8 {
        // Try to read from appmanifest_<appid>.acf in library folders
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

    /// List all installed games
    pub fn listInstalledGames(self: *const Self) ![]GameInfo {
        var games = std.ArrayList(GameInfo).init(self.allocator);

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
                        const info = self.getGameInfo(app_id) catch continue;
                        try games.append(info);
                    } else |_| {}
                }
            }
        }

        return games.toOwnedSlice();
    }

    /// List available Proton versions
    pub fn listProtonVersions(self: *const Self) ![]ProtonInfo {
        var protons = std.ArrayList(ProtonInfo).init(self.allocator);

        // Check Steam's compatibility tools directory
        const compat_path = try std.fmt.allocPrint(
            self.allocator,
            "{s}/compatibilitytools.d",
            .{self.steam_path},
        );
        defer self.allocator.free(compat_path);

        var dir = std.fs.openDirAbsolute(compat_path, .{ .iterate = true }) catch {
            // Also check common locations
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

                try protons.append(.{
                    .name = try self.allocator.dupe(u8, entry.name),
                    .path = tool_path,
                });
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
    fn detectActiveUser(self: *const Self) !?u64 {
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

// ═══════════════════════════════════════════════════════════════════════════════
// DATA TYPES
// ═══════════════════════════════════════════════════════════════════════════════

pub const GameInfo = struct {
    app_id: u32,
    name: []const u8,
    install_dir: []const u8,
    executable: []const u8,
    proton_version: ?[]const u8,
    playtime_minutes: u32,
};

pub const ProtonInfo = struct {
    name: []const u8,
    path: []const u8,
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

