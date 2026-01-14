const std = @import("std");

// ═══════════════════════════════════════════════════════════════════════════════
// TINKER INTERFACE: The Plugin System
// ═══════════════════════════════════════════════════════════════════════════════
//
// The Tinker interface defines the contract for all STL-Next modules.
// Each Tinker can modify the launch environment in specific ways:
//
// 1. preparePrefix: Filesystem operations (copy files, create symlinks)
// 2. modifyEnv: Environment variable injection (MANGOHUD=1, etc.)
// 3. modifyArgs: Command line modifications (gamescope wrapper, etc.)
//
// Tinkers are executed in priority order:
//   - Setup (10-30): File preparation
//   - Overlay (40-60): HUDs and visual mods  
//   - Wrapper (70-90): Command wrappers like Gamescope
//   - Launch (100): Final launch modifications
//
// ═══════════════════════════════════════════════════════════════════════════════

/// Game launch context passed to each Tinker
pub const Context = struct {
    allocator: std.mem.Allocator,
    app_id: u32,
    game_name: []const u8,
    install_dir: []const u8,
    proton_path: ?[]const u8,
    prefix_path: []const u8,
    config_dir: []const u8,
    
    /// Scratch directory for temporary files
    scratch_dir: []const u8,
};

/// Environment variable map
pub const EnvMap = std.process.EnvMap;

/// Argument list for command construction
pub const ArgList = std.ArrayList([]const u8);

/// The Tinker trait - all modules must implement this
pub const Tinker = struct {
    /// Unique identifier for the tinker
    id: []const u8,
    
    /// Human-readable name
    name: []const u8,
    
    /// Priority determines execution order (lower = earlier)
    /// 10-30: Setup, 40-60: Overlay, 70-90: Wrapper, 100: Launch
    priority: u8,
    
    /// Check if this tinker is enabled for the given context
    isEnabledFn: *const fn(ctx: *const Context) bool,
    
    /// Prepare the prefix (filesystem operations)
    /// Called before environment setup
    preparePrefixFn: ?*const fn(ctx: *const Context) anyerror!void,
    
    /// Modify environment variables
    modifyEnvFn: ?*const fn(ctx: *const Context, env: *EnvMap) anyerror!void,
    
    /// Modify command arguments (can wrap the command)
    modifyArgsFn: ?*const fn(ctx: *const Context, args: *ArgList) anyerror!void,
    
    /// Cleanup after launch (optional)
    cleanupFn: ?*const fn(ctx: *const Context) void,
    
    pub fn isEnabled(self: *const Tinker, ctx: *const Context) bool {
        return self.isEnabledFn(ctx);
    }
    
    pub fn preparePrefix(self: *const Tinker, ctx: *const Context) !void {
        if (self.preparePrefixFn) |f| {
            try f(ctx);
        }
    }
    
    pub fn modifyEnv(self: *const Tinker, ctx: *const Context, env: *EnvMap) !void {
        if (self.modifyEnvFn) |f| {
            try f(ctx, env);
        }
    }
    
    pub fn modifyArgs(self: *const Tinker, ctx: *const Context, args: *ArgList) !void {
        if (self.modifyArgsFn) |f| {
            try f(ctx, args);
        }
    }
    
    pub fn cleanup(self: *const Tinker, ctx: *const Context) void {
        if (self.cleanupFn) |f| {
            f(ctx);
        }
    }
};

/// Tinker registry - manages all available tinkers
pub const TinkerRegistry = struct {
    allocator: std.mem.Allocator,
    tinkers: std.ArrayList(*const Tinker),
    
    const Self = @This();
    
    pub fn init(allocator: std.mem.Allocator) Self {
        return .{
            .allocator = allocator,
            .tinkers = std.ArrayList(*const Tinker).init(allocator),
        };
    }
    
    pub fn deinit(self: *Self) void {
        self.tinkers.deinit();
    }
    
    pub fn register(self: *Self, tinker: *const Tinker) !void {
        try self.tinkers.append(tinker);
        // Sort by priority
        std.sort.insertion(*const Tinker, self.tinkers.items, {}, struct {
            fn lessThan(_: void, a: *const Tinker, b: *const Tinker) bool {
                return a.priority < b.priority;
            }
        }.lessThan);
    }
    
    pub fn getEnabled(self: *Self, ctx: *const Context) ![]*const Tinker {
        var enabled = std.ArrayList(*const Tinker).init(self.allocator);
        errdefer enabled.deinit();
        
        for (self.tinkers.items) |tinker| {
            if (tinker.isEnabled(ctx)) {
                try enabled.append(tinker);
            }
        }
        
        return enabled.toOwnedSlice();
    }
    
    pub fn runAll(self: *Self, ctx: *const Context, env: *EnvMap, args: *ArgList) !void {
        const enabled = try self.getEnabled(ctx);
        defer self.allocator.free(enabled);
        
        // Phase 1: Prepare prefixes
        for (enabled) |tinker| {
            std.log.info("Tinker [{s}]: Preparing prefix...", .{tinker.name});
            try tinker.preparePrefix(ctx);
        }
        
        // Phase 2: Modify environment
        for (enabled) |tinker| {
            std.log.debug("Tinker [{s}]: Modifying environment...", .{tinker.name});
            try tinker.modifyEnv(ctx, env);
        }
        
        // Phase 3: Modify arguments
        for (enabled) |tinker| {
            std.log.debug("Tinker [{s}]: Modifying arguments...", .{tinker.name});
            try tinker.modifyArgs(ctx, args);
        }
    }
};

// ═══════════════════════════════════════════════════════════════════════════════
// PRIORITY CONSTANTS
// ═══════════════════════════════════════════════════════════════════════════════

pub const Priority = struct {
    /// Setup phase (file preparation, symlinks)
    pub const SETUP_EARLY: u8 = 10;
    pub const SETUP: u8 = 20;
    pub const SETUP_LATE: u8 = 30;
    
    /// Overlay phase (HUDs, visual mods)
    pub const OVERLAY_EARLY: u8 = 40;
    pub const OVERLAY: u8 = 50;
    pub const OVERLAY_LATE: u8 = 60;
    
    /// Wrapper phase (Gamescope, etc.)
    pub const WRAPPER_EARLY: u8 = 70;
    pub const WRAPPER: u8 = 80;
    pub const WRAPPER_LATE: u8 = 90;
    
    /// Launch phase (final modifications)
    pub const LAUNCH: u8 = 100;
};

// ═══════════════════════════════════════════════════════════════════════════════
// TESTS
// ═══════════════════════════════════════════════════════════════════════════════

test "priority ordering" {
    try std.testing.expect(Priority.SETUP < Priority.OVERLAY);
    try std.testing.expect(Priority.OVERLAY < Priority.WRAPPER);
    try std.testing.expect(Priority.WRAPPER < Priority.LAUNCH);
}

test "tinker registry sorting" {
    var registry = TinkerRegistry.init(std.testing.allocator);
    defer registry.deinit();
    
    const high_priority = Tinker{
        .id = "high",
        .name = "High Priority",
        .priority = Priority.SETUP,
        .isEnabledFn = struct {
            fn f(_: *const Context) bool { return true; }
        }.f,
        .preparePrefixFn = null,
        .modifyEnvFn = null,
        .modifyArgsFn = null,
        .cleanupFn = null,
    };
    
    const low_priority = Tinker{
        .id = "low",
        .name = "Low Priority",
        .priority = Priority.LAUNCH,
        .isEnabledFn = struct {
            fn f(_: *const Context) bool { return true; }
        }.f,
        .preparePrefixFn = null,
        .modifyEnvFn = null,
        .modifyArgsFn = null,
        .cleanupFn = null,
    };
    
    // Add in reverse order
    try registry.register(&low_priority);
    try registry.register(&high_priority);
    
    // Should be sorted by priority
    try std.testing.expectEqual(Priority.SETUP, registry.tinkers.items[0].priority);
    try std.testing.expectEqual(Priority.LAUNCH, registry.tinkers.items[1].priority);
}
