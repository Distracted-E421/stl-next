const std = @import("std");

// ═══════════════════════════════════════════════════════════════════════════════
// D-BUS CLIENT (Phase 8 - Skeleton)
// ═══════════════════════════════════════════════════════════════════════════════
//
// D-Bus integration for:
//   - GPU selection (switcheroo-control)
//   - Power profiles (performance mode)
//   - Session management (screen saver, logout inhibit)
//   - Desktop notifications
//   - GameMode native API
//
// Implementation options:
//   1. sd-bus (systemd, recommended for NixOS)
//   2. libdbus-1 (fallback)
//   3. busctl subprocess (simplest, always available)
//
// ═══════════════════════════════════════════════════════════════════════════════

pub const DbusError = error{
    ConnectionFailed,
    ServiceNotAvailable,
    MethodCallFailed,
    PropertyAccessFailed,
    InvalidResponse,
    Timeout,
};

/// D-Bus message response
pub const DbusResponse = struct {
    allocator: std.mem.Allocator,
    data: []const u8,

    pub fn deinit(self: *DbusResponse) void {
        self.allocator.free(self.data);
    }

    pub fn asString(self: *const DbusResponse) []const u8 {
        return self.data;
    }

    pub fn asInt(self: *const DbusResponse) !i64 {
        return std.fmt.parseInt(i64, std.mem.trim(u8, self.data, " \t\n\""), 10);
    }

    pub fn asBool(self: *const DbusResponse) bool {
        const trimmed = std.mem.trim(u8, self.data, " \t\n\"");
        return std.mem.eql(u8, trimmed, "true") or std.mem.eql(u8, trimmed, "yes");
    }
};

/// D-Bus client using busctl subprocess (works everywhere)
pub const DbusClient = struct {
    allocator: std.mem.Allocator,
    session_bus: bool,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator) Self {
        return .{
            .allocator = allocator,
            .session_bus = true, // Session bus for most services
        };
    }

    pub fn deinit(self: *Self) void {
        _ = self;
    }

    /// Call a D-Bus method using busctl
    pub fn call(
        self: *Self,
        destination: []const u8,
        object_path: []const u8,
        interface: []const u8,
        method: []const u8,
    ) !DbusResponse {
        var argv: std.ArrayList([]const u8) = .{};
        defer argv.deinit(self.allocator);

        try argv.append(self.allocator, "busctl");
        try argv.append(self.allocator, "call");
        if (!self.session_bus) try argv.append(self.allocator, "--system");
        try argv.append(self.allocator, destination);
        try argv.append(self.allocator, object_path);
        try argv.append(self.allocator, interface);
        try argv.append(self.allocator, method);

        const result = std.process.Child.run(.{
            .allocator = self.allocator,
            .argv = argv.items,
        }) catch return error.ConnectionFailed;

        defer self.allocator.free(result.stderr);

        if (result.term.Exited != 0) {
            self.allocator.free(result.stdout);
            return error.MethodCallFailed;
        }

        return DbusResponse{
            .allocator = self.allocator,
            .data = result.stdout,
        };
    }

    /// Get a D-Bus property using busctl
    pub fn getProperty(
        self: *Self,
        destination: []const u8,
        object_path: []const u8,
        interface: []const u8,
        property: []const u8,
    ) !DbusResponse {
        var argv: std.ArrayList([]const u8) = .{};
        defer argv.deinit(self.allocator);

        try argv.append(self.allocator, "busctl");
        try argv.append(self.allocator, "get-property");
        if (!self.session_bus) try argv.append(self.allocator, "--system");
        try argv.append(self.allocator, destination);
        try argv.append(self.allocator, object_path);
        try argv.append(self.allocator, interface);
        try argv.append(self.allocator, property);

        const result = std.process.Child.run(.{
            .allocator = self.allocator,
            .argv = argv.items,
        }) catch return error.ConnectionFailed;

        defer self.allocator.free(result.stderr);

        if (result.term.Exited != 0) {
            self.allocator.free(result.stdout);
            return error.PropertyAccessFailed;
        }

        return DbusResponse{
            .allocator = self.allocator,
            .data = result.stdout,
        };
    }

    /// Set a D-Bus property using busctl
    pub fn setProperty(
        self: *Self,
        destination: []const u8,
        object_path: []const u8,
        interface: []const u8,
        property: []const u8,
        signature: []const u8,
        value: []const u8,
    ) !void {
        var argv: std.ArrayList([]const u8) = .{};
        defer argv.deinit(self.allocator);

        try argv.append(self.allocator, "busctl");
        try argv.append(self.allocator, "set-property");
        if (!self.session_bus) try argv.append(self.allocator, "--system");
        try argv.append(self.allocator, destination);
        try argv.append(self.allocator, object_path);
        try argv.append(self.allocator, interface);
        try argv.append(self.allocator, property);
        try argv.append(self.allocator, signature);
        try argv.append(self.allocator, value);

        const result = std.process.Child.run(.{
            .allocator = self.allocator,
            .argv = argv.items,
        }) catch return error.ConnectionFailed;

        defer self.allocator.free(result.stdout);
        defer self.allocator.free(result.stderr);

        if (result.term.Exited != 0) {
            return error.PropertyAccessFailed;
        }
    }

    /// Check if a D-Bus service is available
    pub fn isServiceAvailable(self: *Self, service: []const u8) bool {
        const result = std.process.Child.run(.{
            .allocator = self.allocator,
            .argv = &.{
                "busctl",
                if (self.session_bus) "--user" else "--system",
                "status",
                service,
            },
        }) catch return false;

        defer self.allocator.free(result.stdout);
        defer self.allocator.free(result.stderr);

        return result.term.Exited == 0;
    }
};

// ═══════════════════════════════════════════════════════════════════════════════
// TESTS
// ═══════════════════════════════════════════════════════════════════════════════

test "dbus client init" {
    const allocator = std.testing.allocator;
    var client = DbusClient.init(allocator);
    defer client.deinit();

    // Just test initialization
    try std.testing.expect(client.session_bus);
}

