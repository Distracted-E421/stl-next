const std = @import("std");
const ray = @cImport({
    @cInclude("raylib.h");
});

// ═══════════════════════════════════════════════════════════════════════════════
// STL-NEXT GUI: WAIT REQUESTER
// ═══════════════════════════════════════════════════════════════════════════════
//
// A modern, dark-themed Wait Requester GUI built with Raylib.
//
// Features:
//   - Game information display with icon
//   - Visual countdown timer with progress bar
//   - Tinker toggles with hover effects
//   - Launch/Pause/Cancel buttons
//   - Optional IPC integration with daemon
//   - Keyboard shortcuts
//   - Window dragging
//
// ═══════════════════════════════════════════════════════════════════════════════

const WINDOW_WIDTH = 640;
const WINDOW_HEIGHT = 440;
const FONT_SIZE = 18;
const TITLE_SIZE = 26;

// Color scheme (Catppuccin Mocha inspired - a popular dark theme)
const Colors = struct {
    const base = ray.Color{ .r = 30, .g = 30, .b = 46, .a = 255 };
    const mantle = ray.Color{ .r = 24, .g = 24, .b = 37, .a = 255 };
    const surface0 = ray.Color{ .r = 49, .g = 50, .b = 68, .a = 255 };
    const surface1 = ray.Color{ .r = 69, .g = 71, .b = 90, .a = 255 };
    const surface2 = ray.Color{ .r = 88, .g = 91, .b = 112, .a = 255 };
    const overlay0 = ray.Color{ .r = 108, .g = 112, .b = 134, .a = 255 };
    const text = ray.Color{ .r = 205, .g = 214, .b = 244, .a = 255 };
    const subtext = ray.Color{ .r = 166, .g = 173, .b = 200, .a = 255 };
    const blue = ray.Color{ .r = 137, .g = 180, .b = 250, .a = 255 };
    const green = ray.Color{ .r = 166, .g = 227, .b = 161, .a = 255 };
    const red = ray.Color{ .r = 243, .g = 139, .b = 168, .a = 255 };
    const yellow = ray.Color{ .r = 249, .g = 226, .b = 175, .a = 255 };
    const mauve = ray.Color{ .r = 203, .g = 166, .b = 247, .a = 255 };
    const peach = ray.Color{ .r = 250, .g = 179, .b = 135, .a = 255 };
    const teal = ray.Color{ .r = 148, .g = 226, .b = 213, .a = 255 };
    const lavender = ray.Color{ .r = 180, .g = 190, .b = 254, .a = 255 };
};

// Tinker definition
const Tinker = struct {
    name: []const u8,
    key: []const u8,
    enabled: bool,
    color: ray.Color,
    description: []const u8,
};

// Application state
const AppState = struct {
    game_name: [256]u8 = undefined,
    game_name_len: usize = 0,
    app_id: u32 = 0,
    countdown: f32 = 10.0,
    countdown_max: f32 = 10.0,
    paused: bool = false,
    launched: bool = false,
    cancelled: bool = false,

    // Tinkers
    tinkers: [6]Tinker = .{
        .{ .name = "MangoHud", .key = "M", .enabled = false, .color = Colors.peach, .description = "FPS overlay" },
        .{ .name = "Gamescope", .key = "G", .enabled = false, .color = Colors.blue, .description = "Compositor" },
        .{ .name = "GameMode", .key = "O", .enabled = true, .color = Colors.green, .description = "System optimization" },
        .{ .name = "Winetricks", .key = "W", .enabled = false, .color = Colors.mauve, .description = "Windows libs" },
        .{ .name = "Custom Cmds", .key = "C", .enabled = false, .color = Colors.teal, .description = "Shell commands" },
        .{ .name = "SteamGridDB", .key = "S", .enabled = false, .color = Colors.lavender, .description = "Game artwork" },
    },

    fn getGameName(self: *const AppState) []const u8 {
        if (self.game_name_len == 0) return "Unknown Game";
        return self.game_name[0..self.game_name_len];
    }

    fn setGameName(self: *AppState, name: []const u8) void {
        const len = @min(name.len, self.game_name.len);
        @memcpy(self.game_name[0..len], name[0..len]);
        self.game_name_len = len;
    }
};

var state: AppState = .{};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Parse command line arguments
    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    if (args.len > 1) {
        state.app_id = std.fmt.parseInt(u32, args[1], 10) catch 0;
    }

    if (args.len > 2) {
        state.setGameName(args[2]);
    } else {
        state.setGameName("Stardew Valley");
    }

    if (args.len > 3) {
        state.countdown = std.fmt.parseFloat(f32, args[3]) catch 10.0;
        state.countdown_max = state.countdown;
    }

    // Initialize window
    ray.SetConfigFlags(ray.FLAG_WINDOW_UNDECORATED | ray.FLAG_MSAA_4X_HINT);
    ray.InitWindow(WINDOW_WIDTH, WINDOW_HEIGHT, "STL-Next Wait Requester");
    ray.SetTargetFPS(60);
    defer ray.CloseWindow();

    // Try to center window (may not work on Wayland, but that's okay)
    const monitor = ray.GetCurrentMonitor();
    const mon_width = ray.GetMonitorWidth(monitor);
    const mon_height = ray.GetMonitorHeight(monitor);
    ray.SetWindowPosition(
        @divTrunc(mon_width - WINDOW_WIDTH, 2),
        @divTrunc(mon_height - WINDOW_HEIGHT, 2),
    );

    // Main loop
    while (!ray.WindowShouldClose() and !state.launched and !state.cancelled) {
        // Handle input
        handleInput();

        // Update countdown
        if (!state.paused and state.countdown > 0) {
            state.countdown -= ray.GetFrameTime();
            if (state.countdown <= 0) {
                state.countdown = 0;
                state.launched = true;
            }
        }

        // Render
        ray.BeginDrawing();
        defer ray.EndDrawing();

        ray.ClearBackground(Colors.base);

        drawHeader();
        drawGameInfo();
        drawCountdown();
        drawTinkerToggles();
        drawButtons();
        drawKeyboardHints();
    }

    // Output result for daemon integration (Zig 0.15.x compatible)
    const stdout_file = std.fs.File{ .handle = std.posix.STDOUT_FILENO };
    var buf: [256]u8 = undefined;

    if (state.launched) {
        const launch_msg = std.fmt.bufPrint(&buf, "LAUNCH:{d}\n", .{state.app_id}) catch "LAUNCH:0\n";
        stdout_file.writeAll(launch_msg) catch {};

        // Output enabled tinkers
        for (state.tinkers) |tinker| {
            if (tinker.enabled) {
                const tinker_msg = std.fmt.bufPrint(&buf, "TINKER:{s}\n", .{tinker.name}) catch continue;
                stdout_file.writeAll(tinker_msg) catch {};
            }
        }
    } else {
        stdout_file.writeAll("CANCELLED\n") catch {};
    }
}

fn handleInput() void {
    // Keyboard shortcuts
    if (ray.IsKeyPressed(ray.KEY_SPACE) or ray.IsKeyPressed(ray.KEY_P)) {
        state.paused = !state.paused;
    }
    if (ray.IsKeyPressed(ray.KEY_ENTER) or ray.IsKeyPressed(ray.KEY_L)) {
        state.launched = true;
    }
    if (ray.IsKeyPressed(ray.KEY_ESCAPE) or ray.IsKeyPressed(ray.KEY_Q)) {
        state.cancelled = true;
    }
    if (ray.IsKeyPressed(ray.KEY_TAB)) {
        // Skip countdown
        state.countdown = 0;
        state.launched = true;
    }

    // Tinker toggles
    if (ray.IsKeyPressed(ray.KEY_M)) state.tinkers[0].enabled = !state.tinkers[0].enabled;
    if (ray.IsKeyPressed(ray.KEY_G)) state.tinkers[1].enabled = !state.tinkers[1].enabled;
    if (ray.IsKeyPressed(ray.KEY_O)) state.tinkers[2].enabled = !state.tinkers[2].enabled;
    if (ray.IsKeyPressed(ray.KEY_W)) state.tinkers[3].enabled = !state.tinkers[3].enabled;
    if (ray.IsKeyPressed(ray.KEY_C)) state.tinkers[4].enabled = !state.tinkers[4].enabled;
    if (ray.IsKeyPressed(ray.KEY_S)) state.tinkers[5].enabled = !state.tinkers[5].enabled;

    // Window dragging (only in header area)
    if (ray.IsMouseButtonDown(ray.MOUSE_BUTTON_LEFT)) {
        const mouse_y = ray.GetMouseY();
        if (mouse_y < 50) { // Header area
            const delta = ray.GetMouseDelta();
            const pos = ray.GetWindowPosition();
            ray.SetWindowPosition(
                @as(i32, @intFromFloat(pos.x + delta.x)),
                @as(i32, @intFromFloat(pos.y + delta.y)),
            );
        }
    }
}

fn drawHeader() void {
    // Title bar background with gradient effect
    ray.DrawRectangle(0, 0, WINDOW_WIDTH, 50, Colors.mantle);
    ray.DrawRectangle(0, 48, WINDOW_WIDTH, 2, Colors.surface0);

    // Logo/Icon area
    ray.DrawRectangleRounded(ray.Rectangle{ .x = 15, .y = 10, .width = 30, .height = 30 }, 0.3, 8, Colors.blue);
    ray.DrawText("S", 24, 15, 20, Colors.base);

    // Title
    ray.DrawText("STL-Next", 55, 14, 22, Colors.text);
    ray.DrawText("Wait Requester", 145, 17, 16, Colors.subtext);

    // Close button (top right)
    const close_rect = ray.Rectangle{
        .x = WINDOW_WIDTH - 40,
        .y = 10,
        .width = 30,
        .height = 30,
    };

    const close_hover = ray.CheckCollisionPointRec(ray.GetMousePosition(), close_rect);
    if (close_hover) {
        ray.DrawRectangleRounded(close_rect, 0.3, 8, Colors.red);
    }
    ray.DrawText("X", WINDOW_WIDTH - 32, 15, 20, if (close_hover) Colors.base else Colors.subtext);

    if (close_hover and ray.IsMouseButtonPressed(ray.MOUSE_BUTTON_LEFT)) {
        state.cancelled = true;
    }
}

fn drawGameInfo() void {
    const y_pos: i32 = 65;

    // Game name
    var name_buf: [256:0]u8 = undefined;
    const game_name = state.getGameName();
    const len = @min(game_name.len, name_buf.len - 1);
    @memcpy(name_buf[0..len], game_name[0..len]);
    name_buf[len] = 0;
    ray.DrawText(&name_buf, 20, y_pos, TITLE_SIZE, Colors.blue);

    // AppID
    var id_buf: [64:0]u8 = undefined;
    _ = std.fmt.bufPrintZ(&id_buf, "AppID: {d}", .{state.app_id}) catch {};
    ray.DrawText(&id_buf, 20, y_pos + 35, FONT_SIZE, Colors.subtext);
}

fn drawCountdown() void {
    const y_pos: i32 = 130;

    // Progress bar container
    const bar_rect = ray.Rectangle{
        .x = 20,
        .y = @floatFromInt(y_pos),
        .width = WINDOW_WIDTH - 40,
        .height = 35,
    };
    ray.DrawRectangleRounded(bar_rect, 0.3, 8, Colors.surface0);

    // Progress bar fill
    const progress = if (state.countdown_max > 0) state.countdown / state.countdown_max else 0;
    const bar_width = @as(f32, @floatFromInt(WINDOW_WIDTH - 48)) * progress;

    const bar_color = if (state.paused) Colors.yellow else if (progress < 0.3) Colors.red else Colors.green;
    const fill_rect = ray.Rectangle{
        .x = 24,
        .y = @floatFromInt(y_pos + 4),
        .width = bar_width,
        .height = 27,
    };
    ray.DrawRectangleRounded(fill_rect, 0.3, 8, bar_color);

    // Countdown text
    var buf: [64:0]u8 = undefined;
    const countdown_int: u32 = @intFromFloat(@ceil(state.countdown));
    const status = if (state.paused) "PAUSED" else "Launching in...";
    _ = std.fmt.bufPrintZ(&buf, "{s} {d}s", .{ status, countdown_int }) catch {};

    const text_width = ray.MeasureText(&buf, FONT_SIZE);
    ray.DrawText(&buf, @divTrunc(WINDOW_WIDTH - text_width, 2), y_pos + 45, FONT_SIZE, Colors.text);
}

fn drawTinkerToggles() void {
    const y_start: i32 = 195;
    const col_width: i32 = 190;
    const row_height: i32 = 42;
    const margin: i32 = 20;

    // Section header
    ray.DrawText("Tinkers:", margin, y_start, FONT_SIZE, Colors.subtext);

    // Draw tinker toggles in 2 columns
    for (&state.tinkers, 0..) |*tinker, i| {
        const col: i32 = @intCast(i % 2);
        const row: i32 = @intCast(i / 2);
        const x = margin + col * (col_width + 15);
        const y = y_start + 30 + row * row_height;

        // Button rectangle
        const rect = ray.Rectangle{
            .x = @floatFromInt(x),
            .y = @floatFromInt(y),
            .width = col_width,
            .height = row_height - 5,
        };

        const hover = ray.CheckCollisionPointRec(ray.GetMousePosition(), rect);

        // Background with hover effect
        const bg_color = if (tinker.enabled)
            (if (hover) Colors.surface2 else Colors.surface1)
        else
            (if (hover) Colors.surface1 else Colors.surface0);
        ray.DrawRectangleRounded(rect, 0.3, 8, bg_color);

        // Left color bar indicator
        if (tinker.enabled) {
            const indicator_rect = ray.Rectangle{
                .x = @floatFromInt(x + 2),
                .y = @floatFromInt(y + 4),
                .width = 4,
                .height = row_height - 13,
            };
            ray.DrawRectangleRounded(indicator_rect, 0.5, 4, tinker.color);
        }

        // Checkbox
        var check_buf: [4:0]u8 = undefined;
        _ = std.fmt.bufPrintZ(&check_buf, "{s}", .{if (tinker.enabled) "[x]" else "[ ]"}) catch {};
        const check_color = if (tinker.enabled) tinker.color else Colors.overlay0;
        ray.DrawText(&check_buf, x + 12, y + 9, 16, check_color);

        // Name and key
        var label_buf: [64:0]u8 = undefined;
        _ = std.fmt.bufPrintZ(&label_buf, "{s} [{s}]", .{ tinker.name, tinker.key }) catch {};
        ray.DrawText(&label_buf, x + 50, y + 6, 15, Colors.text);

        // Description
        var desc_buf: [64:0]u8 = undefined;
        _ = std.fmt.bufPrintZ(&desc_buf, "{s}", .{tinker.description}) catch {};
        ray.DrawText(&desc_buf, x + 50, y + 22, 11, Colors.subtext);

        // Click detection
        if (hover and ray.IsMouseButtonPressed(ray.MOUSE_BUTTON_LEFT)) {
            tinker.enabled = !tinker.enabled;
        }
    }
}

fn drawButtons() void {
    const y_pos: i32 = 355;
    const btn_width: i32 = 150;
    const btn_height: i32 = 45;
    const spacing: i32 = 20;

    // Calculate button positions (centered)
    const total_width = btn_width * 3 + spacing * 2;
    const start_x = @divTrunc(WINDOW_WIDTH - total_width, 2);

    const buttons = [_]struct {
        text: [:0]const u8,
        color: ray.Color,
        hover_color: ray.Color,
        action: enum { launch, pause, cancel },
    }{
        .{ .text = "Launch Now", .color = Colors.green, .hover_color = Colors.green, .action = .launch },
        .{ .text = if (state.paused) "Resume" else "Pause", .color = Colors.yellow, .hover_color = Colors.yellow, .action = .pause },
        .{ .text = "Cancel", .color = Colors.red, .hover_color = Colors.red, .action = .cancel },
    };

    for (buttons, 0..) |btn, i| {
        const x = start_x + @as(i32, @intCast(i)) * (btn_width + spacing);
        const rect = ray.Rectangle{
            .x = @floatFromInt(x),
            .y = @floatFromInt(y_pos),
            .width = btn_width,
            .height = btn_height,
        };

        const hover = ray.CheckCollisionPointRec(ray.GetMousePosition(), rect);

        // Button background
        const bg = if (hover) btn.hover_color else Colors.surface1;
        ray.DrawRectangleRounded(rect, 0.3, 8, bg);

        // Border
        ray.DrawRectangleRoundedLinesEx(rect, 0.3, 8, 2, if (hover) btn.hover_color else Colors.surface2);

        // Text
        const text_width = ray.MeasureText(btn.text, 16);
        const text_color = if (hover) Colors.base else btn.color;
        ray.DrawText(btn.text, x + @divTrunc(btn_width - text_width, 2), y_pos + 14, 16, text_color);

        // Click handling
        if (hover and ray.IsMouseButtonPressed(ray.MOUSE_BUTTON_LEFT)) {
            switch (btn.action) {
                .launch => state.launched = true,
                .pause => state.paused = !state.paused,
                .cancel => state.cancelled = true,
            }
        }
    }
}

fn drawKeyboardHints() void {
    const y_pos = WINDOW_HEIGHT - 25;
    ray.DrawText("Enter: Launch | Space: Pause | Tab: Skip | Esc: Cancel", 20, y_pos, 12, Colors.overlay0);

    // Version
    ray.DrawText("v0.5.3", WINDOW_WIDTH - 50, y_pos, 12, Colors.overlay0);
}
