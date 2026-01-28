const std = @import("std");
const vdf = @import("vdf.zig");
const appinfo = @import("appinfo.zig");
const leveldb = @import("leveldb.zig");

// ═══════════════════════════════════════════════════════════════════════════════
// STEAM ENGINE (Phase 3.5 - Launch Options + Tests)
// ═══════════════════════════════════════════════════════════════════════════════

pub const SteamEngine = struct {
    allocator: std.mem.Allocator,
    steam_path: []const u8,
    library_folders: std.ArrayList([]const u8),
    active_user_id: ?u64,
    installation_type: InstallationType,
    collections: ?leveldb.SteamCollections,

    const Self = @This();

    pub const InstallationType = enum { native, flatpak, snap, unknown };

    pub fn init(allocator: std.mem.Allocator) !Self {
        const steam_path = try discoverSteamPath(allocator);
        const installation_type = detectInstallationType(steam_path);

        var engine = Self{
            .allocator = allocator,
            .steam_path = steam_path,
            .library_folders = .{}, // Zig 0.15.x: unmanaged ArrayList
            .active_user_id = null,
            .installation_type = installation_type,
            .collections = null,
        };

        try engine.loadLibraryFolders();
        engine.active_user_id = engine.detectActiveUser() catch null;
        engine.collections = leveldb.SteamCollections.init(allocator, steam_path) catch null;
        
        if (engine.collections) |*c| {
            if (engine.active_user_id) |uid| {
                c.setUserId(uid);
            }
        }

        return engine;
    }

    pub fn deinit(self: *Self) void {
        if (self.collections) |*c| c.deinit();
        self.allocator.free(self.steam_path);
        for (self.library_folders.items) |path| {
            self.allocator.free(path);
        }
        self.library_folders.deinit(self.allocator);
    }

    /// Get complete game information including launch options
    pub fn getGameInfo(self: *Self, app_id: u32) !GameInfo {
        const game_name = try self.getGameNameFromManifest(app_id);
        const install_dir = try self.getInstallDir(app_id);
        const launch_options = try self.getUserLaunchOptions(app_id);
        const executable = try self.getExecutable(app_id, install_dir);
        
        return GameInfo{
            .app_id = app_id,
            .name = game_name,
            .install_dir = install_dir,
            .executable = executable,
            .launch_options = launch_options,
            .proton_version = null,
            .playtime_minutes = 0,
            .is_hidden = self.isGameHidden(app_id),
            .collections = self.getGameCollections(app_id) catch &[_][]const u8{},
        };
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
        if (stat.size > 10 * 1024 * 1024) return null;
        
        const content = try self.allocator.alloc(u8, stat.size);
        defer self.allocator.free(content);
        _ = try file.readAll(content);
        
        // Search for pattern: "appid"\n\t+{\n...LaunchOptions
        // We need to find app blocks (with {) not hex values
        const app_id_quoted = try std.fmt.allocPrint(self.allocator, "\"{d}\"", .{app_id});
        defer self.allocator.free(app_id_quoted);
        
        var pos: usize = 0;
        while (std.mem.indexOfPos(u8, content, pos, app_id_quoted)) |app_pos| {
            // Look for opening brace within next 20 chars (skip whitespace)
            const check_start = app_pos + app_id_quoted.len;
            const check_end = @min(check_start + 20, content.len);
            
            var brace_found = false;
            var brace_pos: usize = 0;
            for (content[check_start..check_end], 0..) |c, i| {
                if (c == '{') {
                    brace_found = true;
                    brace_pos = check_start + i;
                    break;
                }
                if (c == '"') break;  // Hit another value, not a block
            }
            
            if (brace_found) {
                // Found app block, look for LaunchOptions within next 2000 chars
                const search_end = @min(brace_pos + 2000, content.len);
                
                if (std.mem.indexOfPos(u8, content, brace_pos, "\"LaunchOptions\"")) |lo_pos| {
                    if (lo_pos < search_end) {
                        // Extract the value
                        if (extractVdfStringValue(content, lo_pos)) |value| {
                            // Validate it's an actual launch option (not empty or garbage)
                            if (value.len > 0) {
                                var is_valid = true;
                                for (value) |c| {
                                    if (c == '\n' or c == '{' or c == '}') {
                                        is_valid = false;
                                        break;
                                    }
                                }
                                if (is_valid) {
                                    return try self.allocator.dupe(u8, value);
                                }
                            }
                        }
                    }
                }
            }
            pos = app_pos + 1;
        }
        
        return null;
    }
    
    fn getExecutable(self: *Self, app_id: u32, install_dir: []const u8) !?[]const u8 {
        _ = app_id;
        if (install_dir.len == 0) return null;
        
        var dir = std.fs.openDirAbsolute(install_dir, .{ .iterate = true }) catch return null;
        defer dir.close();
        
        // Get the folder name as potential game name (e.g., "Stardew Valley")
        const folder_name = std.fs.path.basename(install_dir);
        
        // Phase 1: Look for native Linux executable (no extension, matching folder name)
        {
            var iter = dir.iterate();
            while (try iter.next()) |entry| {
                if (entry.kind != .file) continue;
                // Skip files with extensions (these are likely Windows files or libraries)
                if (std.mem.indexOf(u8, entry.name, ".") != null) continue;
                // Check if it's likely an executable (matches folder name)
                if (std.mem.eql(u8, entry.name, folder_name)) {
                    return try std.fmt.allocPrint(
                        self.allocator, "{s}/{s}", .{ install_dir, entry.name },
                    );
                }
            }
        }
        
        // Phase 2: Look for .exe that matches game name
        dir = std.fs.openDirAbsolute(install_dir, .{ .iterate = true }) catch return null;
        {
            var iter = dir.iterate();
            while (try iter.next()) |entry| {
                if (entry.kind != .file) continue;
                if (!std.mem.endsWith(u8, entry.name, ".exe")) continue;
                // Skip known non-game executables
                if (isNonGameExecutable(entry.name)) continue;
                // Prefer exe matching folder name
                const name_without_ext = entry.name[0..entry.name.len - 4];
                if (std.mem.eql(u8, name_without_ext, folder_name)) {
                    return try std.fmt.allocPrint(
                        self.allocator, "{s}/{s}", .{ install_dir, entry.name },
                    );
                }
            }
        }
        
        // Phase 3: Fallback - any valid .exe
        dir = std.fs.openDirAbsolute(install_dir, .{ .iterate = true }) catch return null;
        {
        var iter = dir.iterate();
        while (try iter.next()) |entry| {
            if (entry.kind == .file and std.mem.endsWith(u8, entry.name, ".exe")) {
                    if (isNonGameExecutable(entry.name)) continue;
                return try std.fmt.allocPrint(
                    self.allocator, "{s}/{s}", .{ install_dir, entry.name },
                );
                }
            }
        }
        return null;
    }
    
    fn isNonGameExecutable(name: []const u8) bool {
        // Known non-game executables to skip
        const skip_list = [_][]const u8{
            "UnityCrashHandler",
            "unins",
            "createdump",
            "crashhandler",
            "CrashReporter",
            "Reporter",
            "Launcher", // Usually not the main game
            "Setup",
            "Config",
            "RedistInstaller",
            "vcredist",
            "dxsetup",
            "dotnet",
        };
        
        for (skip_list) |skip| {
            if (std.ascii.indexOfIgnoreCase(name, skip) != null) return true;
        }
        return false;
    }

    fn getGameNameFromManifest(self: *Self, app_id: u32) ![]const u8 {
        for (self.library_folders.items) |lib_path| {
            const manifest_path = try std.fmt.allocPrint(
                self.allocator, "{s}/steamapps/appmanifest_{d}.acf", .{ lib_path, app_id },
            );
            defer self.allocator.free(manifest_path);

            const file = std.fs.openFileAbsolute(manifest_path, .{}) catch continue;
            defer file.close();

            const stat = try file.stat();
            const content = try self.allocator.alloc(u8, stat.size);
            defer self.allocator.free(content);
            _ = try file.readAll(content);

            if (std.mem.indexOf(u8, content, "\"name\"")) |name_pos| {
                if (extractVdfStringValue(content, name_pos)) |name| {
                    return try self.allocator.dupe(u8, name);
                }
            }
        }
        return try std.fmt.allocPrint(self.allocator, "Game {d}", .{app_id});
    }

    fn getInstallDir(self: *Self, app_id: u32) ![]const u8 {
        for (self.library_folders.items) |lib_path| {
            const manifest_path = try std.fmt.allocPrint(
                self.allocator, "{s}/steamapps/appmanifest_{d}.acf", .{ lib_path, app_id },
            );
            defer self.allocator.free(manifest_path);

            const file = std.fs.openFileAbsolute(manifest_path, .{}) catch continue;
            defer file.close();

            const stat = try file.stat();
            const content = try self.allocator.alloc(u8, stat.size);
            defer self.allocator.free(content);
            _ = try file.readAll(content);

            if (std.mem.indexOf(u8, content, "\"installdir\"")) |pos| {
                if (extractVdfStringValue(content, pos)) |dir| {
                    return try std.fmt.allocPrint(
                        self.allocator, "{s}/steamapps/common/{s}", .{ lib_path, dir },
                    );
                }
            }
        }
        return try self.allocator.dupe(u8, "");
    }

    pub fn isGameHidden(self: *Self, app_id: u32) bool {
        var collections = self.collections orelse return false;
        return collections.isHidden(app_id);
    }

    pub fn getGameCollections(self: *Self, app_id: u32) ![]const []const u8 {
        var collections = self.collections orelse return &[_][]const u8{};
        return collections.getGameCollections(app_id);
    }

    pub fn listInstalledGames(self: *Self) ![]GameInfo {
        var games: std.ArrayList(GameInfo) = .{};
        errdefer games.deinit(self.allocator);

        for (self.library_folders.items) |lib_path| {
            const steamapps_path = try std.fmt.allocPrint(
                self.allocator, "{s}/steamapps", .{lib_path},
            );
            defer self.allocator.free(steamapps_path);

            var dir = std.fs.openDirAbsolute(steamapps_path, .{ .iterate = true }) catch continue;
            defer dir.close();

            var iter = dir.iterate();
            while (try iter.next()) |entry| {
                if (std.mem.startsWith(u8, entry.name, "appmanifest_") and
                    std.mem.endsWith(u8, entry.name, ".acf"))
                {
                    const id_start = "appmanifest_".len;
                    const id_end = entry.name.len - ".acf".len;
                    const id_str = entry.name[id_start..id_end];

                    if (std.fmt.parseInt(u32, id_str, 10)) |app_id| {
                        if (self.isGameHidden(app_id)) continue;
                        const info = self.getGameInfo(app_id) catch continue;
                        try games.append(self.allocator, info);
                    } else |_| {}
                }
            }
        }
        return games.toOwnedSlice(self.allocator);
    }

    pub fn listProtonVersions(self: *Self) ![]ProtonInfo {
        var protons: std.ArrayList(ProtonInfo) = .{};
        errdefer protons.deinit(self.allocator);

        // User compatibility tools
        const compat_path = try std.fmt.allocPrint(
            self.allocator, "{s}/compatibilitytools.d", .{self.steam_path},
        );
        defer self.allocator.free(compat_path);

        if (std.fs.openDirAbsolute(compat_path, .{ .iterate = true })) |dir| {
            var compat_dir = dir;
            defer compat_dir.close();
            
            var iter = compat_dir.iterate();
            while (try iter.next()) |entry| {
                if (entry.kind == .directory) {
                    const tool_path = try std.fmt.allocPrint(
                        self.allocator, "{s}/{s}", .{ compat_path, entry.name },
                    );
                    try protons.append(self.allocator, .{
                        .name = try self.allocator.dupe(u8, entry.name),
                        .path = tool_path,
                        .is_proton = std.mem.indexOf(u8, entry.name, "roton") != null,
                    });
                }
            }
        } else |_| {}

        // Steam's built-in Proton versions
        for (self.library_folders.items) |lib_path| {
            const common_path = try std.fmt.allocPrint(
                self.allocator, "{s}/steamapps/common", .{lib_path},
            );
            defer self.allocator.free(common_path);

            var dir = std.fs.openDirAbsolute(common_path, .{ .iterate = true }) catch continue;
            defer dir.close();

            var iter = dir.iterate();
            while (try iter.next()) |entry| {
                if (entry.kind == .directory and std.mem.startsWith(u8, entry.name, "Proton")) {
                    const tool_path = try std.fmt.allocPrint(
                        self.allocator, "{s}/{s}", .{ common_path, entry.name },
                    );
                    try protons.append(self.allocator, .{
                        .name = try self.allocator.dupe(u8, entry.name),
                        .path = tool_path,
                        .is_proton = true,
                    });
                }
            }
        }
        return protons.toOwnedSlice(self.allocator);
    }

    fn loadLibraryFolders(self: *Self) !void {
        try self.library_folders.append(self.allocator, try self.allocator.dupe(u8, self.steam_path));

        const lib_vdf_path = try std.fmt.allocPrint(
            self.allocator, "{s}/steamapps/libraryfolders.vdf", .{self.steam_path},
        );
        defer self.allocator.free(lib_vdf_path);

        const file = std.fs.openFileAbsolute(lib_vdf_path, .{}) catch return;
        defer file.close();

        const stat = try file.stat();
        const content = try self.allocator.alloc(u8, stat.size);
        defer self.allocator.free(content);
        _ = try file.readAll(content);

        var pos: usize = 0;
        while (std.mem.indexOfPos(u8, content, pos, "\"path\"")) |path_pos| {
            if (extractVdfStringValue(content, path_pos)) |path| {
                var found = false;
                for (self.library_folders.items) |existing| {
                    if (std.mem.eql(u8, existing, path)) {
                        found = true;
                        break;
                    }
                }
                if (!found) {
                    try self.library_folders.append(self.allocator, try self.allocator.dupe(u8, path));
                }
            }
            pos = path_pos + 1;
        }
    }

    fn detectActiveUser(self: *Self) !?u64 {
        const userdata_path = try std.fmt.allocPrint(
            self.allocator, "{s}/userdata", .{self.steam_path},
        );
        defer self.allocator.free(userdata_path);

        var dir = std.fs.openDirAbsolute(userdata_path, .{ .iterate = true }) catch return null;
        defer dir.close();

        var iter = dir.iterate();
        while (try iter.next()) |entry| {
            if (entry.kind == .directory) {
                if (std.fmt.parseInt(u64, entry.name, 10)) |uid| {
                    return uid;
                } else |_| {}
            }
        }
        return null;
    }
};

fn extractVdfStringValue(content: []const u8, key_pos: usize) ?[]const u8 {
    var pos = key_pos;
    var quote_count: u8 = 0;
    var value_start: ?usize = null;
    
    while (pos < content.len and quote_count < 4) : (pos += 1) {
        if (content[pos] == '"') {
            quote_count += 1;
            if (quote_count == 3) {
                value_start = pos + 1;
            } else if (quote_count == 4) {
                if (value_start) |start| {
                    return content[start..pos];
                }
            }
        }
    }
    return null;
}

fn discoverSteamPath(allocator: std.mem.Allocator) ![]const u8 {
    const home = std.posix.getenv("HOME") orelse return error.NoHomeDirectory;
    const paths = [_][]const u8{
        "/.steam/steam",
        "/.local/share/Steam",
        "/.var/app/com.valvesoftware.Steam/data/Steam",
    };

    for (paths) |suffix| {
        const path = try std.fmt.allocPrint(allocator, "{s}{s}", .{ home, suffix });
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

fn detectInstallationType(path: []const u8) SteamEngine.InstallationType {
    if (std.mem.indexOf(u8, path, ".var/app/com.valvesoftware.Steam") != null) return .flatpak;
    if (std.mem.indexOf(u8, path, "/snap/") != null) return .snap;
    if (std.mem.indexOf(u8, path, "/.steam/") != null) return .native;
    if (std.mem.indexOf(u8, path, "/.local/share/Steam") != null) return .native;
    return .unknown;
}

// ═══════════════════════════════════════════════════════════════════════════════
// DATA TYPES
// ═══════════════════════════════════════════════════════════════════════════════

pub const GameInfo = struct {
    app_id: u32,
    name: []const u8,
    install_dir: []const u8,
    executable: ?[]const u8,
    launch_options: ?[]const u8,
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

test "extract vdf string value" {
    const content = "\"name\"\t\t\"Stardew Valley\"";
    const result = extractVdfStringValue(content, 0);
    try std.testing.expect(result != null);
    try std.testing.expectEqualStrings("Stardew Valley", result.?);
}

test "extract vdf string with spaces" {
    const content = "\"LaunchOptions\"\t\t\"MANGOHUD=1 %command%\"";
    const result = extractVdfStringValue(content, 0);
    try std.testing.expect(result != null);
    try std.testing.expectEqualStrings("MANGOHUD=1 %command%", result.?);
}

test "extract vdf string with special chars" {
    const content = "\"LaunchOptions\"\t\t\"~/.local/share/Steam/steamapps/common/Stardew\\\\ Valley/StardewModdingAPI %command%\"";
    const result = extractVdfStringValue(content, 0);
    try std.testing.expect(result != null);
    try std.testing.expect(std.mem.indexOf(u8, result.?, "StardewModdingAPI") != null);
}

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
