const std = @import("std");

// ═══════════════════════════════════════════════════════════════════════════════
// GUI IPC CLIENT
// ═══════════════════════════════════════════════════════════════════════════════
//
// Simplified IPC client for the GUI to communicate with the daemon.
// Uses Unix Domain Sockets.
//
// ═══════════════════════════════════════════════════════════════════════════════

pub const IpcClient = struct {
    allocator: std.mem.Allocator,
    socket_path: []const u8,
    app_id: u32,
    connected: bool = false,

    const Self = @This();
    const MAX_RESPONSE_SIZE = 4096;

    pub fn init(allocator: std.mem.Allocator, app_id: u32) !Self {
        // Get XDG_RUNTIME_DIR or fallback
        const runtime_dir = std.posix.getenv("XDG_RUNTIME_DIR") orelse "/tmp";
        const path = try std.fmt.allocPrint(allocator, "{s}/stl-next-{d}.sock", .{ runtime_dir, app_id });
        
        return Self{
            .allocator = allocator,
            .socket_path = path,
            .app_id = app_id,
        };
    }

    pub fn deinit(self: *Self) void {
        self.allocator.free(self.socket_path);
    }

    /// Check if the daemon is running by checking if the socket file exists
    pub fn isDaemonRunning(self: *const Self) bool {
        std.fs.accessAbsolute(self.socket_path, .{}) catch return false;
        return true;
    }

    /// Try to connect to the daemon
    pub fn connect(self: *Self) bool {
        // Just check if socket exists for now
        // Full connection will be attempted when sending messages
        self.connected = self.isDaemonRunning();
        return self.connected;
    }

    /// Send an action to the daemon
    pub fn sendAction(self: *Self, action: []const u8) !?[]const u8 {
        if (!self.connected) return null;

        // Create socket
        const sock = std.posix.socket(
            std.posix.AF.UNIX,
            std.posix.SOCK.STREAM,
            0,
        ) catch return null;
        defer std.posix.close(sock);

        // Connect to daemon
        var addr: std.posix.sockaddr.un = .{ .family = std.posix.AF.UNIX, .path = undefined };
        const path_len = @min(self.socket_path.len, addr.path.len - 1);
        @memcpy(addr.path[0..path_len], self.socket_path[0..path_len]);
        addr.path[path_len] = 0;

        std.posix.connect(sock, @ptrCast(&addr), @sizeOf(std.posix.sockaddr.un)) catch {
            self.connected = false;
            return null;
        };

        // Send message as JSON
        var buf: [256]u8 = undefined;
        const msg = std.fmt.bufPrint(&buf, "{{\"action\":\"{s}\"}}\n", .{action}) catch return null;
        _ = std.posix.send(sock, msg, 0) catch return null;

        // Receive response
        var response_buf: [MAX_RESPONSE_SIZE]u8 = undefined;
        const bytes_read = std.posix.recv(sock, &response_buf, 0) catch return null;
        
        if (bytes_read == 0) return null;
        
        const response = try self.allocator.dupe(u8, response_buf[0..bytes_read]);
        return response;
    }

    /// Send PAUSE_LAUNCH action
    pub fn pause(self: *Self) void {
        _ = self.sendAction("PAUSE_LAUNCH") catch {};
    }

    /// Send RESUME_LAUNCH action
    pub fn resumeCountdown(self: *Self) void {
        _ = self.sendAction("RESUME_LAUNCH") catch {};
    }

    /// Send PROCEED action (launch now)
    pub fn proceed(self: *Self) void {
        _ = self.sendAction("PROCEED") catch {};
    }

    /// Send ABORT action
    pub fn abort(self: *Self) void {
        _ = self.sendAction("ABORT") catch {};
    }

    /// Toggle a tinker
    pub fn toggleTinker(self: *Self, tinker_name: []const u8) void {
        var buf: [128]u8 = undefined;
        const action = std.fmt.bufPrint(&buf, "TOGGLE_TINKER:{s}", .{tinker_name}) catch return;
        _ = self.sendAction(action) catch {};
    }

    /// Get current status from daemon (returns JSON or null)
    pub fn getStatus(self: *Self) ?[]const u8 {
        return self.sendAction("GET_STATUS") catch null;
    }
};

// ═══════════════════════════════════════════════════════════════════════════════
// Status parsing helpers
// ═══════════════════════════════════════════════════════════════════════════════

pub const DaemonStatus = struct {
    countdown_seconds: ?u32 = null,
    paused: bool = false,
    game_name: ?[]const u8 = null,
};

/// Parse daemon status response (simplified JSON parsing)
pub fn parseStatus(allocator: std.mem.Allocator, json: []const u8) ?DaemonStatus {
    _ = allocator;
    var status = DaemonStatus{};
    
    // Look for countdown
    if (std.mem.indexOf(u8, json, "\"countdown_seconds\":")) |idx| {
        const start = idx + 20;
        if (start < json.len) {
            var end = start;
            while (end < json.len and json[end] >= '0' and json[end] <= '9') : (end += 1) {}
            if (end > start) {
                status.countdown_seconds = std.fmt.parseInt(u32, json[start..end], 10) catch null;
            }
        }
    }
    
    // Look for paused
    if (std.mem.indexOf(u8, json, "\"paused\":true")) |_| {
        status.paused = true;
    }
    
    return status;
}

