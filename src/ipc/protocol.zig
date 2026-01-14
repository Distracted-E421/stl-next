const std = @import("std");

// ═══════════════════════════════════════════════════════════════════════════════
// IPC PROTOCOL (Phase 4 - Refined)
// ═══════════════════════════════════════════════════════════════════════════════
//
// Clean JSON-based protocol over Unix Domain Sockets
//
// ═══════════════════════════════════════════════════════════════════════════════

/// Actions the client can send to the daemon
pub const Action = enum {
    PAUSE_LAUNCH,
    RESUME_LAUNCH,
    UPDATE_CONFIG,
    PROCEED,
    ABORT,
    GET_STATUS,
    GET_GAME_INFO,
    GET_TINKERS,
    TOGGLE_TINKER,
    
    pub fn toString(self: Action) []const u8 {
        return switch (self) {
            .PAUSE_LAUNCH => "PAUSE_LAUNCH",
            .RESUME_LAUNCH => "RESUME_LAUNCH",
            .UPDATE_CONFIG => "UPDATE_CONFIG",
            .PROCEED => "PROCEED",
            .ABORT => "ABORT",
            .GET_STATUS => "GET_STATUS",
            .GET_GAME_INFO => "GET_GAME_INFO",
            .GET_TINKERS => "GET_TINKERS",
            .TOGGLE_TINKER => "TOGGLE_TINKER",
        };
    }
    
    pub fn fromString(s: []const u8) ?Action {
        const actions = [_]struct { name: []const u8, action: Action }{
            .{ .name = "PAUSE_LAUNCH", .action = .PAUSE_LAUNCH },
            .{ .name = "RESUME_LAUNCH", .action = .RESUME_LAUNCH },
            .{ .name = "UPDATE_CONFIG", .action = .UPDATE_CONFIG },
            .{ .name = "PROCEED", .action = .PROCEED },
            .{ .name = "ABORT", .action = .ABORT },
            .{ .name = "GET_STATUS", .action = .GET_STATUS },
            .{ .name = "GET_GAME_INFO", .action = .GET_GAME_INFO },
            .{ .name = "GET_TINKERS", .action = .GET_TINKERS },
            .{ .name = "TOGGLE_TINKER", .action = .TOGGLE_TINKER },
        };
        for (actions) |a| {
            if (std.mem.eql(u8, s, a.name) or std.mem.indexOf(u8, s, a.name) != null) {
                return a.action;
            }
        }
        return null;
    }
};

/// Daemon states
pub const DaemonState = enum {
    INITIALIZING,
    WAITING,
    COUNTDOWN,
    LAUNCHING,
    RUNNING,
    FINISHED,
    ERROR,
    
    pub fn toString(self: DaemonState) []const u8 {
        return switch (self) {
            .INITIALIZING => "INITIALIZING",
            .WAITING => "WAITING",
            .COUNTDOWN => "COUNTDOWN",
            .LAUNCHING => "LAUNCHING",
            .RUNNING => "RUNNING",
            .FINISHED => "FINISHED",
            .ERROR => "ERROR",
        };
    }
    
    pub fn fromString(s: []const u8) DaemonState {
        if (std.mem.indexOf(u8, s, "WAITING") != null) return .WAITING;
        if (std.mem.indexOf(u8, s, "COUNTDOWN") != null) return .COUNTDOWN;
        if (std.mem.indexOf(u8, s, "LAUNCHING") != null) return .LAUNCHING;
        if (std.mem.indexOf(u8, s, "RUNNING") != null) return .RUNNING;
        if (std.mem.indexOf(u8, s, "FINISHED") != null) return .FINISHED;
        if (std.mem.indexOf(u8, s, "ERROR") != null) return .ERROR;
        return .INITIALIZING;
    }
};

/// Message from Client to Daemon
pub const ClientMessage = struct {
    action: Action,
    tinker_id: ?[]const u8 = null,
    enabled: ?bool = null,
    
    pub fn serialize(self: *const ClientMessage, allocator: std.mem.Allocator) ![]u8 {
        var buf = std.ArrayList(u8).init(allocator);
        errdefer buf.deinit();
        
        try buf.appendSlice("{\"action\":\"");
        try buf.appendSlice(self.action.toString());
        try buf.appendSlice("\"");
        
        if (self.tinker_id) |tid| {
            try buf.appendSlice(",\"tinker_id\":\"");
            try buf.appendSlice(tid);
            try buf.appendSlice("\"");
        }
        
        if (self.enabled) |e| {
            try buf.appendSlice(",\"enabled\":");
            try buf.appendSlice(if (e) "true" else "false");
        }
        
        try buf.appendSlice("}");
        return buf.toOwnedSlice();
    }
};

/// Message from Daemon to Client
pub const DaemonMessage = struct {
    state: DaemonState = .INITIALIZING,
    countdown_seconds: u8 = 0,
    game_name: []const u8 = "",
    app_id: u32 = 0,
    error_msg: ?[]const u8 = null,
    
    // Tinker states
    mangohud_enabled: bool = false,
    gamescope_enabled: bool = false,
    gamemode_enabled: bool = false,
    
    pub fn serialize(self: *const DaemonMessage, allocator: std.mem.Allocator) ![]u8 {
        var buf = std.ArrayList(u8).init(allocator);
        errdefer buf.deinit();
        
        try buf.appendSlice("{");
        
        // State
        try buf.appendSlice("\"state\":\"");
        try buf.appendSlice(self.state.toString());
        try buf.appendSlice("\",");
        
        // Countdown
        try buf.appendSlice("\"countdown_seconds\":");
        var num_buf: [8]u8 = undefined;
        const num_str = std.fmt.bufPrint(&num_buf, "{d}", .{self.countdown_seconds}) catch "0";
        try buf.appendSlice(num_str);
        try buf.appendSlice(",");
        
        // Game name (escape quotes)
        try buf.appendSlice("\"game_name\":\"");
        for (self.game_name) |c| {
            if (c == '"') {
                try buf.appendSlice("\\\"");
            } else if (c == '\\') {
                try buf.appendSlice("\\\\");
            } else {
                try buf.append(c);
            }
        }
        try buf.appendSlice("\",");
        
        // App ID
        try buf.appendSlice("\"app_id\":");
        const app_str = std.fmt.bufPrint(&num_buf, "{d}", .{self.app_id}) catch "0";
        try buf.appendSlice(app_str);
        try buf.appendSlice(",");
        
        // Tinker states
        try buf.appendSlice("\"mangohud_enabled\":");
        try buf.appendSlice(if (self.mangohud_enabled) "true" else "false");
        try buf.appendSlice(",");
        
        try buf.appendSlice("\"gamescope_enabled\":");
        try buf.appendSlice(if (self.gamescope_enabled) "true" else "false");
        try buf.appendSlice(",");
        
        try buf.appendSlice("\"gamemode_enabled\":");
        try buf.appendSlice(if (self.gamemode_enabled) "true" else "false");
        
        // Error (optional)
        if (self.error_msg) |err| {
            try buf.appendSlice(",\"error_msg\":\"");
            try buf.appendSlice(err);
            try buf.appendSlice("\"");
        }
        
        try buf.appendSlice("}");
        return buf.toOwnedSlice();
    }
    
    pub fn parseFromJson(allocator: std.mem.Allocator, data: []const u8) !DaemonMessage {
        _ = allocator;
        var msg = DaemonMessage{};
        
        // Parse state
        msg.state = DaemonState.fromString(data);
        
        // Parse countdown_seconds
        if (std.mem.indexOf(u8, data, "\"countdown_seconds\":")) |pos| {
            const start = pos + 20;
            if (start < data.len) {
                var end = start;
                while (end < data.len and data[end] >= '0' and data[end] <= '9') : (end += 1) {}
                if (end > start) {
                    msg.countdown_seconds = std.fmt.parseInt(u8, data[start..end], 10) catch 0;
                }
            }
        }
        
        // Parse app_id
        if (std.mem.indexOf(u8, data, "\"app_id\":")) |pos| {
            const start = pos + 9;
            if (start < data.len) {
                var end = start;
                while (end < data.len and data[end] >= '0' and data[end] <= '9') : (end += 1) {}
                if (end > start) {
                    msg.app_id = std.fmt.parseInt(u32, data[start..end], 10) catch 0;
                }
            }
        }
        
        // Parse booleans
        msg.mangohud_enabled = std.mem.indexOf(u8, data, "\"mangohud_enabled\":true") != null;
        msg.gamescope_enabled = std.mem.indexOf(u8, data, "\"gamescope_enabled\":true") != null;
        msg.gamemode_enabled = std.mem.indexOf(u8, data, "\"gamemode_enabled\":true") != null;
        
        return msg;
    }
};

// ═══════════════════════════════════════════════════════════════════════════════
// SOCKET PATH HELPERS
// ═══════════════════════════════════════════════════════════════════════════════

pub fn getSocketPath(allocator: std.mem.Allocator, app_id: u32) ![]const u8 {
    const runtime_dir = std.posix.getenv("XDG_RUNTIME_DIR") orelse "/tmp";
    return std.fmt.allocPrint(allocator, "{s}/stl-next-{d}.sock", .{ runtime_dir, app_id });
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

test "daemon message serialization" {
    const msg = DaemonMessage{
        .state = .COUNTDOWN,
        .countdown_seconds = 5,
        .game_name = "Test Game",
        .app_id = 12345,
        .mangohud_enabled = true,
    };
    const serialized = try msg.serialize(std.testing.allocator);
    defer std.testing.allocator.free(serialized);
    
    try std.testing.expect(std.mem.indexOf(u8, serialized, "COUNTDOWN") != null);
    try std.testing.expect(std.mem.indexOf(u8, serialized, "Test Game") != null);
    try std.testing.expect(std.mem.indexOf(u8, serialized, "12345") != null);
    try std.testing.expect(std.mem.indexOf(u8, serialized, "\"mangohud_enabled\":true") != null);
}

test "daemon message parsing" {
    const json = "{\"state\":\"COUNTDOWN\",\"countdown_seconds\":7,\"app_id\":413150,\"mangohud_enabled\":true}";
    const msg = try DaemonMessage.parseFromJson(std.testing.allocator, json);
    
    try std.testing.expectEqual(DaemonState.COUNTDOWN, msg.state);
    try std.testing.expectEqual(@as(u8, 7), msg.countdown_seconds);
    try std.testing.expectEqual(@as(u32, 413150), msg.app_id);
    try std.testing.expect(msg.mangohud_enabled);
}

test "action fromString" {
    try std.testing.expectEqual(Action.PAUSE_LAUNCH, Action.fromString("PAUSE_LAUNCH").?);
    try std.testing.expectEqual(Action.PROCEED, Action.fromString("{\"action\":\"PROCEED\"}").?);
}
