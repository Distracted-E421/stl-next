const std = @import("std");

// ═══════════════════════════════════════════════════════════════════════════════
// VORTEX MOD MANAGER INTEGRATION
// ═══════════════════════════════════════════════════════════════════════════════
//
// Integrates with Vortex Mod Manager running under Wine/Proton.
// Handles:
//   - Vortex discovery and path resolution
//   - NXM link forwarding to Vortex
//   - Mod staging directory detection
//   - AppData sync management
//
// ═══════════════════════════════════════════════════════════════════════════════

pub const VortexError = error{
    VortexNotFound,
    InvalidPath,
    WinePrefixNotFound,
    AppDataSyncFailed,
    VortexNotRunning,
    ConfigReadError,
    OutOfMemory,
};

/// Vortex installation info
pub const VortexInfo = struct {
    path: []const u8,
    wine_prefix: []const u8,
    staging_dir: ?[]const u8,
    appdata_dir: []const u8,
    version: ?[]const u8,
    is_running: bool,

    pub fn deinit(self: *VortexInfo, allocator: std.mem.Allocator) void {
        allocator.free(self.path);
        allocator.free(self.wine_prefix);
        if (self.staging_dir) |s| allocator.free(s);
        allocator.free(self.appdata_dir);
        if (self.version) |v| allocator.free(v);
    }
};

/// Vortex game configuration
pub const VortexGameConfig = struct {
    game_id: []const u8,
    game_path: []const u8,
    mod_path: []const u8,
    staging_folder: ?[]const u8,
    download_folder: ?[]const u8,
    
    pub fn deinit(self: *VortexGameConfig, allocator: std.mem.Allocator) void {
        allocator.free(self.game_id);
        allocator.free(self.game_path);
        allocator.free(self.mod_path);
        if (self.staging_folder) |s| allocator.free(s);
        if (self.download_folder) |d| allocator.free(d);
    }
};

/// Vortex mod manager integration
pub const Vortex = struct {
    allocator: std.mem.Allocator,
    info: ?VortexInfo,
    custom_wine_prefix: ?[]const u8,
    custom_vortex_path: ?[]const u8,

    const Self = @This();

    /// Common Vortex installation paths to search
    const VORTEX_SEARCH_PATHS = [_][]const u8{
        "drive_c/Program Files/Black Tree Gaming Ltd/Vortex/Vortex.exe",
        "drive_c/Program Files (x86)/Black Tree Gaming Ltd/Vortex/Vortex.exe",
        "drive_c/users/steamuser/AppData/Local/Programs/Vortex/Vortex.exe",
        "pfx/drive_c/Program Files/Black Tree Gaming Ltd/Vortex/Vortex.exe",
    };

    /// Common Wine prefix locations
    const WINE_PREFIX_PATHS = [_][]const u8{
        ".local/share/Steam/steamapps/compatdata",
        ".steam/steam/steamapps/compatdata",
        ".local/share/lutris/runners/wine",
        ".wine",
    };

    pub fn init(allocator: std.mem.Allocator) Self {
        return Self{
            .allocator = allocator,
            .info = null,
            .custom_wine_prefix = null,
            .custom_vortex_path = null,
        };
    }

    pub fn deinit(self: *Self) void {
        if (self.info) |*info| {
            info.deinit(self.allocator);
        }
        if (self.custom_wine_prefix) |p| {
            self.allocator.free(p);
        }
        if (self.custom_vortex_path) |p| {
            self.allocator.free(p);
        }
    }

    /// Set custom Wine prefix path
    pub fn setWinePrefix(self: *Self, prefix: []const u8) !void {
        if (self.custom_wine_prefix) |p| {
            self.allocator.free(p);
        }
        self.custom_wine_prefix = try self.allocator.dupe(u8, prefix);
    }

    /// Set custom Vortex executable path
    pub fn setVortexPath(self: *Self, path: []const u8) !void {
        if (self.custom_vortex_path) |p| {
            self.allocator.free(p);
        }
        self.custom_vortex_path = try self.allocator.dupe(u8, path);
    }

    /// Discover Vortex installation
    pub fn discover(self: *Self) VortexError!VortexInfo {
        // If custom path is set, use it directly
        if (self.custom_vortex_path) |path| {
            return self.createVortexInfo(path, self.custom_wine_prefix orelse "/");
        }

        const home = std.posix.getenv("HOME") orelse return VortexError.VortexNotFound;

        // Search known Wine prefix locations
        for (WINE_PREFIX_PATHS) |prefix_path| {
            const full_prefix = std.fmt.allocPrint(self.allocator, "{s}/{s}", .{ home, prefix_path }) catch continue;
            defer self.allocator.free(full_prefix);

            // Check if this is a compatdata directory (Steam)
            if (std.mem.indexOf(u8, prefix_path, "compatdata") != null) {
                // Search for Vortex in all compatdata prefixes
                if (self.searchCompatdata(full_prefix)) |info| {
                    self.info = info;
                    return info;
                }
            } else {
                // Direct Wine prefix
                for (VORTEX_SEARCH_PATHS) |vortex_path| {
                    const full_path = std.fmt.allocPrint(self.allocator, "{s}/{s}", .{ full_prefix, vortex_path }) catch continue;
                    defer self.allocator.free(full_path);

                    if (self.fileExists(full_path)) {
                        const info = self.createVortexInfo(full_path, full_prefix) catch continue;
                        self.info = info;
                        return info;
                    }
                }
            }
        }

        return VortexError.VortexNotFound;
    }

    fn searchCompatdata(self: *Self, compatdata_path: []const u8) ?VortexInfo {
        var dir = std.fs.openDirAbsolute(compatdata_path, .{ .iterate = true }) catch return null;
        defer dir.close();

        var iter = dir.iterate();
        while (iter.next() catch null) |entry| {
            if (entry.kind != .directory) continue;

            // Each subdirectory is an AppID prefix
            for (VORTEX_SEARCH_PATHS) |vortex_path| {
                const full_path = std.fmt.allocPrint(
                    self.allocator,
                    "{s}/{s}/{s}",
                    .{ compatdata_path, entry.name, vortex_path },
                ) catch continue;
                defer self.allocator.free(full_path);

                if (self.fileExists(full_path)) {
                    const prefix = std.fmt.allocPrint(
                        self.allocator,
                        "{s}/{s}",
                        .{ compatdata_path, entry.name },
                    ) catch continue;

                    const info = self.createVortexInfo(full_path, prefix) catch {
                        self.allocator.free(prefix);
                        continue;
                    };
                    // Don't free prefix, it's now owned by info
                    return info;
                }
            }
        }

        return null;
    }

    fn createVortexInfo(self: *Self, vortex_path: []const u8, wine_prefix: []const u8) !VortexInfo {
        const path = try self.allocator.dupe(u8, vortex_path);
        errdefer self.allocator.free(path);

        const prefix = try self.allocator.dupe(u8, wine_prefix);
        errdefer self.allocator.free(prefix);

        // Build AppData path
        const appdata = try std.fmt.allocPrint(
            self.allocator,
            "{s}/drive_c/users/steamuser/AppData/Roaming/Vortex",
            .{wine_prefix},
        );
        errdefer self.allocator.free(appdata);

        // Try to detect staging directory
        const staging = self.detectStagingDir(wine_prefix);

        return VortexInfo{
            .path = path,
            .wine_prefix = prefix,
            .staging_dir = staging,
            .appdata_dir = appdata,
            .version = null, // TODO: Parse version from exe
            .is_running = self.isVortexRunning(),
        };
    }

    fn detectStagingDir(self: *Self, wine_prefix: []const u8) ?[]const u8 {
        // Common staging locations
        const staging_paths = [_][]const u8{
            "drive_c/vortex_staging",
            "drive_c/users/steamuser/AppData/Roaming/Vortex/staging",
        };

        for (staging_paths) |rel_path| {
            const full_path = std.fmt.allocPrint(
                self.allocator,
                "{s}/{s}",
                .{ wine_prefix, rel_path },
            ) catch continue;

            if (self.dirExists(full_path)) {
                return full_path;
            }
            self.allocator.free(full_path);
        }

        return null;
    }

    fn fileExists(self: *Self, path: []const u8) bool {
        _ = self;
        std.fs.accessAbsolute(path, .{}) catch return false;
        return true;
    }

    fn dirExists(self: *Self, path: []const u8) bool {
        _ = self;
        var dir = std.fs.openDirAbsolute(path, .{}) catch return false;
        dir.close();
        return true;
    }

    fn isVortexRunning(self: *Self) bool {
        _ = self;
        // Check if Vortex.exe is in process list
        const result = std.process.Child.run(.{
            .allocator = std.heap.page_allocator,
            .argv = &[_][]const u8{ "pgrep", "-f", "Vortex.exe" },
        }) catch return false;
        defer {
            std.heap.page_allocator.free(result.stdout);
            std.heap.page_allocator.free(result.stderr);
        }
        return result.term.Exited == 0;
    }

    /// Launch Vortex with optional NXM link
    pub fn launch(self: *Self, nxm_link: ?[]const u8) !void {
        const info = self.info orelse return VortexError.VortexNotFound;

        var args = std.ArrayList([]const u8).init(self.allocator);
        defer args.deinit();

        // Use Wine/Proton to launch
        try args.append("wine");
        try args.append(info.path);
        
        if (nxm_link) |link| {
            // URL-encode the NXM link for Wine
            const encoded = try self.urlEncode(link);
            defer self.allocator.free(encoded);
            try args.append(encoded);
        }

        // Set up environment
        var env = std.process.EnvMap.init(self.allocator);
        defer env.deinit();
        
        try env.put("WINEPREFIX", info.wine_prefix);

        var child = std.process.Child.init(args.items, self.allocator);
        child.env_map = &env;
        
        _ = try child.spawnAndWait();
    }

    /// Forward NXM link to running Vortex
    pub fn forwardNxmLink(self: *Self, nxm_link: []const u8) !void {
        const info = self.info orelse return VortexError.VortexNotFound;

        if (!info.is_running) {
            // Launch Vortex with the link
            return self.launch(nxm_link);
        }

        // Vortex is running - use IPC to forward the link
        // Vortex uses a local server for NXM handling
        // The link should be written to a specific location or sent via command
        
        // Method 1: Write to download queue file
        const queue_path = try std.fmt.allocPrint(
            self.allocator,
            "{s}/temp/nxm_queue.txt",
            .{info.appdata_dir},
        );
        defer self.allocator.free(queue_path);

        // Ensure temp directory exists
        const temp_dir = try std.fmt.allocPrint(
            self.allocator,
            "{s}/temp",
            .{info.appdata_dir},
        );
        defer self.allocator.free(temp_dir);
        
        std.fs.makeDirAbsolute(temp_dir) catch |e| {
            if (e != error.PathAlreadyExists) return VortexError.AppDataSyncFailed;
        };

        // Write NXM link to queue
        const file = try std.fs.createFileAbsolute(queue_path, .{});
        defer file.close();
        try file.writeAll(nxm_link);

        std.log.info("Forwarded NXM link to Vortex queue: {s}", .{queue_path});
    }

    /// Sync AppData from Wine prefix to real location
    pub fn syncAppData(self: *Self, real_appdata: []const u8) !void {
        const info = self.info orelse return VortexError.VortexNotFound;

        // Use rsync for reliable syncing
        const result = std.process.Child.run(.{
            .allocator = self.allocator,
            .argv = &[_][]const u8{
                "rsync", "-av", "--delete",
                info.appdata_dir,
                real_appdata,
            },
        }) catch return VortexError.AppDataSyncFailed;

        self.allocator.free(result.stdout);
        self.allocator.free(result.stderr);

        if (result.term.Exited != 0) {
            return VortexError.AppDataSyncFailed;
        }
    }

    /// Get game configuration from Vortex
    pub fn getGameConfig(self: *Self, game_id: []const u8) !VortexGameConfig {
        const info = self.info orelse return VortexError.VortexNotFound;

        // Vortex stores game configs in state files
        const state_path = try std.fmt.allocPrint(
            self.allocator,
            "{s}/state/persistent/{s}",
            .{ info.appdata_dir, game_id },
        );
        defer self.allocator.free(state_path);

        // TODO: Parse actual Vortex state file (JSON format)
        // For now, return a placeholder
        return VortexGameConfig{
            .game_id = try self.allocator.dupe(u8, game_id),
            .game_path = try self.allocator.dupe(u8, ""),
            .mod_path = try self.allocator.dupe(u8, ""),
            .staging_folder = null,
            .download_folder = null,
        };
    }

    fn urlEncode(self: *Self, input: []const u8) ![]const u8 {
        var result = std.ArrayList(u8).init(self.allocator);
        errdefer result.deinit();

        for (input) |c| {
            if (std.ascii.isAlphanumeric(c) or c == '-' or c == '_' or c == '.' or c == '~') {
                try result.append(c);
            } else {
                // Percent-encode
                var buf: [3]u8 = undefined;
                _ = std.fmt.bufPrint(&buf, "%{X:0>2}", .{c}) catch continue;
                try result.appendSlice(&buf);
            }
        }

        return result.toOwnedSlice();
    }
};

// ═══════════════════════════════════════════════════════════════════════════════
// TESTS
// ═══════════════════════════════════════════════════════════════════════════════

test "url encoding" {
    const allocator = std.testing.allocator;
    var vortex = Vortex.init(allocator);
    defer vortex.deinit();

    const encoded = try vortex.urlEncode("nxm://stardewvalley/mods/123/files/456");
    defer allocator.free(encoded);

    try std.testing.expectEqualStrings(
        "nxm%3A%2F%2Fstardewvalley%2Fmods%2F123%2Ffiles%2F456",
        encoded,
    );
}

test "vortex init and deinit" {
    const allocator = std.testing.allocator;
    var vortex = Vortex.init(allocator);
    defer vortex.deinit();
    
    // Should not crash
    try std.testing.expect(vortex.info == null);
}

