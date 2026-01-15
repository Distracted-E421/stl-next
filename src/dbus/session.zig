const std = @import("std");
const client = @import("client.zig");

// ═══════════════════════════════════════════════════════════════════════════════
// SESSION MANAGER (Phase 8 - D-Bus)
// ═══════════════════════════════════════════════════════════════════════════════
//
// Desktop session management via D-Bus:
//
//   - Power profile switching (performance mode during gaming)
//   - Screen saver inhibit (no lock during gaming)
//   - Desktop notifications
//   - Session inhibit (prevent logout)
//
// ═══════════════════════════════════════════════════════════════════════════════

pub const SessionError = error{
    ServiceNotAvailable,
    InhibitFailed,
    NotificationFailed,
    ProfileSwitchFailed,
};

/// Power profile (power-profiles-daemon)
pub const PowerProfile = enum {
    power_saver,
    balanced,
    performance,

    pub fn toString(self: PowerProfile) []const u8 {
        return switch (self) {
            .power_saver => "power-saver",
            .balanced => "balanced",
            .performance => "performance",
        };
    }

    pub fn fromString(s: []const u8) ?PowerProfile {
        const trimmed = std.mem.trim(u8, s, " \t\n\"");
        if (std.mem.eql(u8, trimmed, "power-saver")) return .power_saver;
        if (std.mem.eql(u8, trimmed, "balanced")) return .balanced;
        if (std.mem.eql(u8, trimmed, "performance")) return .performance;
        return null;
    }
};

/// Session Manager
pub const SessionManager = struct {
    allocator: std.mem.Allocator,
    dbus: client.DbusClient,

    // State tracking
    original_power_profile: ?PowerProfile,
    screensaver_cookie: ?u32,
    session_cookie: ?u32,
    notification_id: ?u32,

    // Service availability
    has_power_profiles: bool,
    has_screensaver: bool,
    has_notifications: bool,

    const Self = @This();

    // D-Bus services
    const POWER_PROFILES_SERVICE = "net.hadess.PowerProfiles";
    const POWER_PROFILES_PATH = "/net/hadess/PowerProfiles";
    const POWER_PROFILES_INTERFACE = "net.hadess.PowerProfiles";

    const SCREENSAVER_SERVICE = "org.freedesktop.ScreenSaver";
    const SCREENSAVER_PATH = "/org/freedesktop/ScreenSaver";
    const SCREENSAVER_INTERFACE = "org.freedesktop.ScreenSaver";

    const NOTIFICATIONS_SERVICE = "org.freedesktop.Notifications";
    const NOTIFICATIONS_PATH = "/org/freedesktop/Notifications";
    const NOTIFICATIONS_INTERFACE = "org.freedesktop.Notifications";

    pub fn init(allocator: std.mem.Allocator) Self {
        var self = Self{
            .allocator = allocator,
            .dbus = client.DbusClient.init(allocator),
            .original_power_profile = null,
            .screensaver_cookie = null,
            .session_cookie = null,
            .notification_id = null,
            .has_power_profiles = false,
            .has_screensaver = false,
            .has_notifications = false,
        };

        // Check service availability
        self.has_power_profiles = self.dbus.isServiceAvailable(POWER_PROFILES_SERVICE);
        self.has_screensaver = self.dbus.isServiceAvailable(SCREENSAVER_SERVICE);
        self.has_notifications = self.dbus.isServiceAvailable(NOTIFICATIONS_SERVICE);

        std.log.info("Session: PowerProfiles={}, ScreenSaver={}, Notifications={}", .{
            self.has_power_profiles,
            self.has_screensaver,
            self.has_notifications,
        });

        return self;
    }

    pub fn deinit(self: *Self) void {
        self.dbus.deinit();
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // POWER PROFILES
    // ═══════════════════════════════════════════════════════════════════════════

    /// Get current power profile
    pub fn getCurrentPowerProfile(self: *Self) ?PowerProfile {
        if (!self.has_power_profiles) return null;

        var response = self.dbus.getProperty(
            POWER_PROFILES_SERVICE,
            POWER_PROFILES_PATH,
            POWER_PROFILES_INTERFACE,
            "ActiveProfile",
        ) catch return null;
        defer response.deinit();

        return PowerProfile.fromString(response.asString());
    }

    /// Set power profile
    pub fn setPowerProfile(self: *Self, profile: PowerProfile) !void {
        if (!self.has_power_profiles) return error.ServiceNotAvailable;

        try self.dbus.setProperty(
            POWER_PROFILES_SERVICE,
            POWER_PROFILES_PATH,
            POWER_PROFILES_INTERFACE,
            "ActiveProfile",
            "s",
            profile.toString(),
        );

        std.log.info("Session: Power profile set to {s}", .{profile.toString()});
    }

    /// Switch to performance mode, saving original
    pub fn enablePerformanceMode(self: *Self) !void {
        if (!self.has_power_profiles) return;

        // Save original profile
        self.original_power_profile = self.getCurrentPowerProfile();

        // Switch to performance
        self.setPowerProfile(.performance) catch |err| {
            std.log.warn("Session: Failed to set performance mode: {s}", .{@errorName(err)});
        };
    }

    /// Restore original power profile
    pub fn restorePowerProfile(self: *Self) !void {
        if (self.original_power_profile) |profile| {
            self.setPowerProfile(profile) catch |err| {
                std.log.warn("Session: Failed to restore power profile: {s}", .{@errorName(err)});
            };
            self.original_power_profile = null;
        }
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // SCREEN SAVER INHIBIT
    // ═══════════════════════════════════════════════════════════════════════════

    /// Inhibit screen saver
    pub fn inhibitScreenSaver(self: *Self, reason: []const u8) !void {
        if (!self.has_screensaver) return error.ServiceNotAvailable;
        if (self.screensaver_cookie != null) return; // Already inhibited

        // Use dbus-send for Inhibit method (busctl doesn't handle return values well)
        const result = std.process.Child.run(.{
            .allocator = self.allocator,
            .argv = &.{
                "dbus-send",
                "--session",
                "--dest=" ++ SCREENSAVER_SERVICE,
                "--type=method_call",
                "--print-reply",
                SCREENSAVER_PATH,
                SCREENSAVER_INTERFACE ++ ".Inhibit",
                "string:STL-Next",
                try std.fmt.allocPrint(self.allocator, "string:{s}", .{reason}),
            },
        }) catch return error.InhibitFailed;

        defer self.allocator.free(result.stdout);
        defer self.allocator.free(result.stderr);

        if (result.term.Exited != 0) {
            return error.InhibitFailed;
        }

        // Parse cookie from response
        // Response format: "method return time=... sender=... -> dest=...\n   uint32 12345"
        if (std.mem.indexOf(u8, result.stdout, "uint32 ")) |idx| {
            const cookie_str = std.mem.trim(u8, result.stdout[idx + 7 ..], " \t\n");
            self.screensaver_cookie = std.fmt.parseInt(u32, cookie_str, 10) catch null;
        }

        std.log.info("Session: Screen saver inhibited (cookie: {?})", .{self.screensaver_cookie});
    }

    /// Un-inhibit screen saver
    pub fn uninhibitScreenSaver(self: *Self) !void {
        if (!self.has_screensaver) return;

        const cookie = self.screensaver_cookie orelse return;

        _ = std.process.Child.run(.{
            .allocator = self.allocator,
            .argv = &.{
                "dbus-send",
                "--session",
                "--dest=" ++ SCREENSAVER_SERVICE,
                "--type=method_call",
                SCREENSAVER_PATH,
                SCREENSAVER_INTERFACE ++ ".UnInhibit",
                try std.fmt.allocPrint(self.allocator, "uint32:{d}", .{cookie}),
            },
        }) catch {};

        self.screensaver_cookie = null;
        std.log.info("Session: Screen saver un-inhibited", .{});
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // NOTIFICATIONS
    // ═══════════════════════════════════════════════════════════════════════════

    /// Send a desktop notification
    pub fn notify(
        self: *Self,
        summary: []const u8,
        body: []const u8,
        icon: []const u8,
        timeout_ms: i32,
    ) !void {
        if (!self.has_notifications) return error.ServiceNotAvailable;

        // Use notify-send for simplicity (handles escaping, etc.)
        const result = std.process.Child.run(.{
            .allocator = self.allocator,
            .argv = &.{
                "notify-send",
                "--app-name=STL-Next",
                try std.fmt.allocPrint(self.allocator, "--icon={s}", .{icon}),
                try std.fmt.allocPrint(self.allocator, "--expire-time={d}", .{timeout_ms}),
                summary,
                body,
            },
        }) catch return error.NotificationFailed;

        defer self.allocator.free(result.stdout);
        defer self.allocator.free(result.stderr);
    }

    /// Send game launch notification
    pub fn notifyGameLaunch(self: *Self, game_name: []const u8, app_id: u32) !void {
        const body = try std.fmt.allocPrint(
            self.allocator,
            "Starting {s} (AppID: {d})",
            .{ game_name, app_id },
        );
        defer self.allocator.free(body);

        try self.notify("Game Launching", body, "steam", 5000);
    }

    /// Send game exit notification
    pub fn notifyGameExit(self: *Self, game_name: []const u8, exit_code: ?i32) !void {
        const body = if (exit_code) |code|
            try std.fmt.allocPrint(self.allocator, "{s} exited with code {d}", .{ game_name, code })
        else
            try std.fmt.allocPrint(self.allocator, "{s} closed", .{game_name});
        defer self.allocator.free(body);

        try self.notify("Game Closed", body, "steam", 3000);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // GAMING SESSION MANAGEMENT
    // ═══════════════════════════════════════════════════════════════════════════

    /// Begin a gaming session (enable all protections)
    pub fn beginGamingSession(self: *Self, game_name: []const u8, app_id: u32) !void {
        std.log.info("Session: Beginning gaming session for {s}", .{game_name});

        // 1. Switch to performance mode
        self.enablePerformanceMode() catch {};

        // 2. Inhibit screen saver
        self.inhibitScreenSaver("Gaming session active") catch {};

        // 3. Send notification
        self.notifyGameLaunch(game_name, app_id) catch {};
    }

    /// End a gaming session (restore all settings)
    pub fn endGamingSession(self: *Self, game_name: []const u8, exit_code: ?i32) !void {
        std.log.info("Session: Ending gaming session for {s}", .{game_name});

        // 1. Un-inhibit screen saver
        self.uninhibitScreenSaver() catch {};

        // 2. Restore power profile
        self.restorePowerProfile() catch {};

        // 3. Send notification
        self.notifyGameExit(game_name, exit_code) catch {};
    }
};

// ═══════════════════════════════════════════════════════════════════════════════
// TESTS
// ═══════════════════════════════════════════════════════════════════════════════

test "session manager init" {
    const allocator = std.testing.allocator;
    var mgr = SessionManager.init(allocator);
    defer mgr.deinit();

    // Just test initialization - actual D-Bus calls depend on system
}

test "power profile enum" {
    try std.testing.expectEqual(PowerProfile.performance, PowerProfile.fromString("performance").?);
    try std.testing.expectEqual(PowerProfile.balanced, PowerProfile.fromString("balanced").?);
    try std.testing.expectEqual(PowerProfile.power_saver, PowerProfile.fromString("power-saver").?);
    try std.testing.expect(PowerProfile.fromString("invalid") == null);
}

