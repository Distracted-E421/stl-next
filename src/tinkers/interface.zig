const std = @import("std");
const config = @import("../core/config.zig");

// ═══════════════════════════════════════════════════════════════════════════════
// TINKER INTERFACE (Phase 3.5 - Hardened)
// ═══════════════════════════════════════════════════════════════════════════════
//
// No global state! All configuration passed through Context.
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
    scratch_dir: []const u8,
    
    /// Game configuration - contains all tinker settings
    game_config: *const config.GameConfig,
};

/// Environment variable map
pub const EnvMap = std.process.EnvMap;

/// Argument list for command construction
pub const ArgList = std.ArrayList([]const u8);

/// The Tinker trait - all modules must implement this
pub const Tinker = struct {
    id: []const u8,
    name: []const u8,
    priority: u8,
    
    isEnabledFn: *const fn(ctx: *const Context) bool,
    preparePrefixFn: ?*const fn(ctx: *const Context) anyerror!void,
    modifyEnvFn: ?*const fn(ctx: *const Context, env: *EnvMap) anyerror!void,
    modifyArgsFn: ?*const fn(ctx: *const Context, args: *ArgList) anyerror!void,
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

/// Tinker registry
pub const TinkerRegistry = struct {
    allocator: std.mem.Allocator,
    tinkers: std.ArrayList(*const Tinker),

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator) Self {
        return .{
            .allocator = allocator,
            .tinkers = .{},
        };
    }

    pub fn deinit(self: *Self) void {
        self.tinkers.deinit(self.allocator);
    }

    pub fn register(self: *Self, tinker: *const Tinker) !void {
        try self.tinkers.append(self.allocator, tinker);
        std.sort.insertion(*const Tinker, self.tinkers.items, {}, struct {
            fn lessThan(_: void, a: *const Tinker, b: *const Tinker) bool {
                return a.priority < b.priority;
            }
        }.lessThan);
    }

    pub fn getEnabled(self: *Self, ctx: *const Context) ![]*const Tinker {
        var enabled: std.ArrayList(*const Tinker) = .{};
        errdefer enabled.deinit(self.allocator);

        for (self.tinkers.items) |tinker| {
            if (tinker.isEnabled(ctx)) {
                try enabled.append(self.allocator, tinker);
            }
        }

        return enabled.toOwnedSlice(self.allocator);
    }

    pub fn runAll(self: *Self, ctx: *const Context, env: *EnvMap, args: *ArgList) !void {
        const enabled = try self.getEnabled(ctx);
        defer self.allocator.free(enabled);

        // Phase 1: Prepare prefixes
        for (enabled) |tinker| {
            std.log.info("Tinker [{s}]: Preparing...", .{tinker.name});
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

/// Priority constants
pub const Priority = struct {
    pub const SETUP_EARLY: u8 = 10;
    pub const SETUP: u8 = 20;
    pub const SETUP_LATE: u8 = 30;
    pub const OVERLAY_EARLY: u8 = 40;
    pub const OVERLAY: u8 = 50;
    pub const OVERLAY_LATE: u8 = 60;
    pub const WRAPPER_EARLY: u8 = 70;
    pub const WRAPPER: u8 = 80;
    pub const WRAPPER_LATE: u8 = 90;
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
