const std = @import("std");
const json = std.json;

// ═══════════════════════════════════════════════════════════════════════════════
// IPC PROTOCOL (Phase 4)
// ═══════════════════════════════════════════════════════════════════════════════
//
// JSON-based protocol over Unix Domain Sockets
// Communication between STL Launcher (Daemon) and GUI (Client)
//
// ═══════════════════════════════════════════════════════════════════════════════

/// Actions the client can send to the daemon
pub const Action = enum {
    PAUSE_LAUNCH,      // Pause the countdown timer
    RESUME_LAUNCH,     // Resume countdown
    UPDATE_CONFIG,     // Send new configuration
    PROCEED,           // Launch the game immediately
    ABORT,             // Cancel launch entirely
    GET_STATUS,        // Request current status
    GET_GAME_INFO,     // Request game information
    GET_TINKERS,       // List available tinkers
    TOGGLE_TINKER,     // Enable/disable a tinker
};

/// Daemon states
pub const DaemonState = enum {
    INITIALIZING,
    WAITING,           // Showing GUI/waiting for user
    COUNTDOWN,         // Countdown to auto-launch
    LAUNCHING,         // Preparing to launch
    RUNNING,           // Game is running
    FINISHED,          // Game exited
    ERROR,
};

/// Message from Client to Daemon
pub const ClientMessage = struct {
    action: Action,
    payload: ?[]const u8 = null, // JSON payload for complex actions
    
    pub fn serialize(self: *const ClientMessage, allocator: std.mem.Allocator) ![]u8 {
        return try json.stringifyAlloc(allocator, self, .{});
    }
    
    pub fn deserialize(allocator: std.mem.Allocator, data: []const u8) !ClientMessage {
        return try json.parseFromSlice(ClientMessage, allocator, data, .{});
    }
};

/// Message from Daemon to Client
pub const DaemonMessage = struct {
    state: DaemonState,
    countdown_seconds: u8 = 0,
    game_name: []const u8 = "",
    app_id: u32 = 0,
    error_msg: ?[]const u8 = null,
    tinkers_enabled: []const []const u8 = &.{},
    
    pub fn serialize(self: *const DaemonMessage, allocator: std.mem.Allocator) ![]u8 {
        return try json.stringifyAlloc(allocator, self, .{});
    }
};

/// Tinker toggle request
pub const TinkerToggle = struct {
    tinker_id: []const u8,
    enabled: bool,
};

/// Config update payload
pub const ConfigUpdate = struct {
    mangohud_enabled: ?bool = null,
    gamescope_enabled: ?bool = null,
    gamemode_enabled: ?bool = null,
    proton_version: ?[]const u8 = null,
};

// ═══════════════════════════════════════════════════════════════════════════════
// SOCKET PATH HELPERS
// ═══════════════════════════════════════════════════════════════════════════════

/// Get the socket path for a given AppID
pub fn getSocketPath(allocator: std.mem.Allocator, app_id: u32) ![]const u8 {
    // Use XDG_RUNTIME_DIR if available, otherwise /tmp
    const runtime_dir = std.posix.getenv("XDG_RUNTIME_DIR") orelse "/tmp";
    return std.fmt.allocPrint(allocator, "{s}/stl-next-{d}.sock", .{ runtime_dir, app_id });
}

/// Create a simple status response
pub fn statusResponse(
    allocator: std.mem.Allocator,
    state: DaemonState,
    game_name: []const u8,
    app_id: u32,
    countdown: u8,
) ![]u8 {
    const msg = DaemonMessage{
        .state = state,
        .countdown_seconds = countdown,
        .game_name = game_name,
        .app_id = app_id,
    };
    return msg.serialize(allocator);
}

// ═══════════════════════════════════════════════════════════════════════════════
// TESTS
// ═══════════════════════════════════════════════════════════════════════════════

test "socket path generation" {
    const path = try getSocketPath(std.testing.allocator, 413150);
    defer std.testing.allocator.free(path);
    try std.testing.expect(std.mem.endsWith(u8, path, "stl-next-413150.sock"));
}

test "client message serialization" {
    const msg = ClientMessage{ .action = .PAUSE_LAUNCH };
    const serialized = try msg.serialize(std.testing.allocator);
    defer std.testing.allocator.free(serialized);
    try std.testing.expect(std.mem.indexOf(u8, serialized, "PAUSE_LAUNCH") != null);
}

