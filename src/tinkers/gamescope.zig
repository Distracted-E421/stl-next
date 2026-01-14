const std = @import("std");
const interface = @import("interface.zig");

// ═══════════════════════════════════════════════════════════════════════════════
// GAMESCOPE TINKER: Wayland Compositor Wrapper
// ═══════════════════════════════════════════════════════════════════════════════
//
// Gamescope is a micro-compositor from Valve that provides:
// - FSR (FidelityFX Super Resolution) upscaling
// - Custom resolution rendering
// - Frame limiting
// - HDR passthrough
//
// This tinker wraps the game command with gamescope arguments.
//
// ═══════════════════════════════════════════════════════════════════════════════

/// Gamescope configuration
pub const GamescopeConfig = struct {
    enabled: bool = false,
    
    // Resolution
    width: u16 = 0,           // Output width (0 = native)
    height: u16 = 0,          // Output height (0 = native)
    internal_width: u16 = 0,  // Internal render width
    internal_height: u16 = 0, // Internal render height
    
    // Display mode
    fullscreen: bool = true,
    borderless: bool = false,
    
    // Upscaling
    fsr: bool = false,
    fsr_sharpness: u8 = 5,    // 0-20, lower = sharper
    nis: bool = false,        // NVIDIA Image Scaling
    
    // Performance
    fps_limit: u16 = 0,       // 0 = unlimited
    vrr: bool = false,        // Variable Refresh Rate
    
    // Steam Deck specific
    steam_deck_mode: bool = false,
    
    /// Build the gamescope command arguments
    pub fn buildArgs(self: *const GamescopeConfig, allocator: std.mem.Allocator) ![][]const u8 {
        var args = std.ArrayList([]const u8).init(allocator);
        errdefer {
            for (args.items) |arg| allocator.free(arg);
            args.deinit();
        }
        
        try args.append(try allocator.dupe(u8, "gamescope"));
        
        // Output resolution
        if (self.width > 0 and self.height > 0) {
            try args.append(try std.fmt.allocPrint(allocator, "-W", .{}));
            try args.append(try std.fmt.allocPrint(allocator, "{d}", .{self.width}));
            try args.append(try std.fmt.allocPrint(allocator, "-H", .{}));
            try args.append(try std.fmt.allocPrint(allocator, "{d}", .{self.height}));
        }
        
        // Internal resolution
        if (self.internal_width > 0 and self.internal_height > 0) {
            try args.append(try std.fmt.allocPrint(allocator, "-w", .{}));
            try args.append(try std.fmt.allocPrint(allocator, "{d}", .{self.internal_width}));
            try args.append(try std.fmt.allocPrint(allocator, "-h", .{}));
            try args.append(try std.fmt.allocPrint(allocator, "{d}", .{self.internal_height}));
        }
        
        // Display mode
        if (self.fullscreen) {
            try args.append(try allocator.dupe(u8, "-f"));
        }
        if (self.borderless) {
            try args.append(try allocator.dupe(u8, "-b"));
        }
        
        // Upscaling
        if (self.fsr) {
            try args.append(try allocator.dupe(u8, "-F"));
            try args.append(try allocator.dupe(u8, "fsr"));
            try args.append(try std.fmt.allocPrint(allocator, "--fsr-sharpness", .{}));
            try args.append(try std.fmt.allocPrint(allocator, "{d}", .{self.fsr_sharpness}));
        }
        if (self.nis) {
            try args.append(try allocator.dupe(u8, "-F"));
            try args.append(try allocator.dupe(u8, "nis"));
        }
        
        // Performance
        if (self.fps_limit > 0) {
            try args.append(try std.fmt.allocPrint(allocator, "{d}", .{self.fps_limit}));
        }
        if (self.vrr) {
            try args.append(try allocator.dupe(u8, "--adaptive-sync"));
        }
        
        // Steam Deck mode
        if (self.steam_deck_mode) {
            try args.append(try allocator.dupe(u8, "-e"));  // Steam integration
        }
        
        // End of gamescope args, game command follows
        try args.append(try allocator.dupe(u8, "--"));
        
        return args.toOwnedSlice();
    }
};

// Global config
var global_config: GamescopeConfig = .{ .enabled = false };

/// Set the Gamescope config
pub fn setConfig(config: GamescopeConfig) void {
    global_config = config;
}

/// Check if Gamescope is enabled
fn isEnabled(ctx: *const interface.Context) bool {
    _ = ctx; // Context not needed for global config check
    return global_config.enabled;
}

/// Modify command arguments to wrap with Gamescope
fn modifyArgs(ctx: *const interface.Context, args: *interface.ArgList) !void {
    const gs_args = try global_config.buildArgs(ctx.allocator);
    
    // Prepend gamescope args to the command
    // We need to insert at the beginning
    var new_args = std.ArrayList([]const u8).init(ctx.allocator);
    
    // Add gamescope first
    for (gs_args) |arg| {
        try new_args.append(arg);
    }
    
    // Then add original args
    for (args.items) |arg| {
        try new_args.append(arg);
    }
    
    // Replace args
    args.clearRetainingCapacity();
    for (new_args.items) |arg| {
        try args.append(arg);
    }
    new_args.deinit();
    
    std.log.info("Gamescope: Wrapping with resolution {d}x{d}", .{
        global_config.width, global_config.height,
    });
}

/// The Gamescope tinker instance
pub const gamescope_tinker = interface.Tinker{
    .id = "gamescope",
    .name = "Gamescope",
    .priority = interface.Priority.WRAPPER, // Runs late to wrap command
    .isEnabledFn = isEnabled,
    .preparePrefixFn = null,
    .modifyEnvFn = null,
    .modifyArgsFn = modifyArgs,
    .cleanupFn = null,
};

// ═══════════════════════════════════════════════════════════════════════════════
// TESTS
// ═══════════════════════════════════════════════════════════════════════════════

test "gamescope args building" {
    const config = GamescopeConfig{
        .enabled = true,
        .width = 1920,
        .height = 1080,
        .fullscreen = true,
        .fsr = true,
    };
    
    const args = try config.buildArgs(std.testing.allocator);
    defer {
        for (args) |arg| std.testing.allocator.free(arg);
        std.testing.allocator.free(args);
    }
    
    try std.testing.expectEqualStrings("gamescope", args[0]);
    
    // Check that -- is present
    var has_separator = false;
    for (args) |arg| {
        if (std.mem.eql(u8, arg, "--")) {
            has_separator = true;
            break;
        }
    }
    try std.testing.expect(has_separator);
}
