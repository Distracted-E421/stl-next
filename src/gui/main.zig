const std = @import("std");
const ray = @cImport({
    @cInclude("raylib.h");
});
const ipc = @import("ipc.zig");

// ═══════════════════════════════════════════════════════════════════════════════
// STL-NEXT GUI: WAIT REQUESTER v2
// ═══════════════════════════════════════════════════════════════════════════════
//
// Redesigned for better readability and usability:
//   - Larger, clearer fonts
//   - Tooltips on hover
//   - Intuitive layout with clear sections
//   - IPC integration with daemon
//   - Visual feedback for all interactions
//
// ═══════════════════════════════════════════════════════════════════════════════

// Window dimensions - slightly larger for better readability
const WINDOW_WIDTH = 720;
const WINDOW_HEIGHT = 520;

// Font sizes - larger for readability
const FONT_TINY = 14;
const FONT_SMALL = 18;
const FONT_MEDIUM = 22;
const FONT_LARGE = 28;
const FONT_TITLE = 36;

// Color scheme (Catppuccin Mocha - high contrast variant)
const Colors = struct {
    // Backgrounds
    const base = ray.Color{ .r = 24, .g = 24, .b = 32, .a = 255 }; // Darker for contrast
    const mantle = ray.Color{ .r = 18, .g = 18, .b = 26, .a = 255 };
    const surface0 = ray.Color{ .r = 40, .g = 42, .b = 54, .a = 255 };
    const surface1 = ray.Color{ .r = 55, .g = 58, .b = 75, .a = 255 };
    const surface2 = ray.Color{ .r = 75, .g = 80, .b = 100, .a = 255 };
    
    // Text - brighter for readability
    const text = ray.Color{ .r = 240, .g = 245, .b = 255, .a = 255 }; // Brighter white
    const subtext = ray.Color{ .r = 180, .g = 190, .b = 210, .a = 255 };
    const muted = ray.Color{ .r = 120, .g = 130, .b = 150, .a = 255 };
    
    // Accents
    const blue = ray.Color{ .r = 120, .g = 170, .b = 255, .a = 255 };
    const green = ray.Color{ .r = 130, .g = 220, .b = 140, .a = 255 };
    const red = ray.Color{ .r = 255, .g = 120, .b = 140, .a = 255 };
    const yellow = ray.Color{ .r = 255, .g = 220, .b = 100, .a = 255 };
    const orange = ray.Color{ .r = 255, .g = 160, .b = 100, .a = 255 };
    const purple = ray.Color{ .r = 180, .g = 140, .b = 255, .a = 255 };
    const cyan = ray.Color{ .r = 100, .g = 220, .b = 220, .a = 255 };
    const pink = ray.Color{ .r = 255, .g = 150, .b = 200, .a = 255 };
    
    // Tooltip
    const tooltip_bg = ray.Color{ .r = 50, .g = 50, .b = 70, .a = 240 };
    const tooltip_border = ray.Color{ .r = 100, .g = 100, .b = 130, .a = 255 };
};

// Tinker definition with tooltip
const Tinker = struct {
    id: []const u8,
    name: []const u8,
    key: u8, // Single key character
    enabled: bool,
    color: ray.Color,
    tooltip: []const u8,
};

// Tooltip state
const TooltipState = struct {
    visible: bool = false,
    text: []const u8 = "",
    x: i32 = 0,
    y: i32 = 0,
    timer: f32 = 0,
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
    connected_to_daemon: bool = false,
    ipc_client: ?*ipc.IpcClient = null,
    poll_timer: f32 = 0,
    
    // Tooltip
    tooltip: TooltipState = .{},
    hover_timer: f32 = 0,
    last_hover_rect: ?ray.Rectangle = null,
    
    // Tinkers - with tooltips explaining each one
    tinkers: [6]Tinker = .{
        .{ .id = "mangohud", .name = "MangoHud", .key = 'M', .enabled = false, .color = Colors.orange, 
           .tooltip = "Shows FPS, frame time, CPU/GPU usage overlay" },
        .{ .id = "gamescope", .name = "Gamescope", .key = 'G', .enabled = false, .color = Colors.blue,
           .tooltip = "Valve's compositor for resolution scaling and FSR" },
        .{ .id = "gamemode", .name = "GameMode", .key = 'O', .enabled = true, .color = Colors.green,
           .tooltip = "Optimizes system for gaming (CPU governor, etc.)" },
        .{ .id = "winetricks", .name = "Winetricks", .key = 'W', .enabled = false, .color = Colors.purple,
           .tooltip = "Install Windows components (DirectX, .NET, etc.)" },
        .{ .id = "customcmd", .name = "Custom Cmd", .key = 'C', .enabled = false, .color = Colors.cyan,
           .tooltip = "Run shell commands before/after game launch" },
        .{ .id = "steamgriddb", .name = "SteamGridDB", .key = 'S', .enabled = false, .color = Colors.pink,
           .tooltip = "Download game artwork (icons, banners, etc.)" },
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
    
    fn showTooltip(self: *AppState, text: []const u8, x: i32, y: i32) void {
        self.tooltip.text = text;
        self.tooltip.x = x;
        self.tooltip.y = y;
        self.tooltip.visible = true;
    }
    
    fn hideTooltip(self: *AppState) void {
        self.tooltip.visible = false;
        self.hover_timer = 0;
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
    
    // Try to connect to daemon via IPC
    var ipc_client: ?ipc.IpcClient = ipc.IpcClient.init(allocator, state.app_id) catch null;
    defer if (ipc_client) |*c| c.deinit();
    
    if (ipc_client) |*c| {
        state.connected_to_daemon = c.connect();
        state.ipc_client = c;
        if (state.connected_to_daemon) {
            std.debug.print("Connected to daemon at: {s}\n", .{c.socket_path});
        }
    }
    
    // Initialize window
    ray.SetConfigFlags(ray.FLAG_WINDOW_UNDECORATED | ray.FLAG_MSAA_4X_HINT);
    ray.InitWindow(WINDOW_WIDTH, WINDOW_HEIGHT, "STL-Next");
    ray.SetTargetFPS(60);
    defer ray.CloseWindow();
    
    // Try to center window
    const monitor = ray.GetCurrentMonitor();
    const mon_width = ray.GetMonitorWidth(monitor);
    const mon_height = ray.GetMonitorHeight(monitor);
    ray.SetWindowPosition(
        @divTrunc(mon_width - WINDOW_WIDTH, 2),
        @divTrunc(mon_height - WINDOW_HEIGHT, 2),
    );
    
    // Main loop
    while (!ray.WindowShouldClose() and !state.launched and !state.cancelled) {
        const dt = ray.GetFrameTime();
        
        // Update hover timer for tooltips
        updateTooltipTimer(dt);
        
        // Handle input
        handleInput();
        
        // Update countdown
        if (!state.paused and state.countdown > 0) {
            state.countdown -= dt;
            if (state.countdown <= 0) {
                state.countdown = 0;
                state.launched = true;
            }
        }
        
        // Render
        ray.BeginDrawing();
        defer ray.EndDrawing();
        
        ray.ClearBackground(Colors.base);
        
        drawTitleBar();
        drawGameSection();
        drawCountdownSection();
        drawTinkersSection();
        drawActionsSection();
        drawStatusBar();
        
        // Draw tooltip last (on top)
        drawTooltip();
    }
    
    // Output result for daemon integration
    outputResult();
}

fn updateTooltipTimer(dt: f32) void {
    if (state.last_hover_rect) |rect| {
        if (ray.CheckCollisionPointRec(ray.GetMousePosition(), rect)) {
            state.hover_timer += dt;
            if (state.hover_timer > 0.5 and !state.tooltip.visible) {
                // Show tooltip after 0.5s hover
            }
        } else {
            state.hideTooltip();
            state.last_hover_rect = null;
        }
    }
}

fn handleInput() void {
    // Keyboard shortcuts with IPC forwarding
    if (ray.IsKeyPressed(ray.KEY_SPACE) or ray.IsKeyPressed(ray.KEY_P)) {
        state.paused = !state.paused;
        if (state.ipc_client) |c| {
            if (state.paused) c.pause() else c.resumeCountdown();
        }
    }
    if (ray.IsKeyPressed(ray.KEY_ENTER) or ray.IsKeyPressed(ray.KEY_L)) {
        state.launched = true;
        if (state.ipc_client) |c| c.proceed();
    }
    if (ray.IsKeyPressed(ray.KEY_ESCAPE) or ray.IsKeyPressed(ray.KEY_Q)) {
        state.cancelled = true;
        if (state.ipc_client) |c| c.abort();
    }
    if (ray.IsKeyPressed(ray.KEY_TAB)) {
        state.countdown = 0;
        state.launched = true;
        if (state.ipc_client) |c| c.proceed();
    }
    
    // Tinker toggles by key with IPC forwarding
    for (&state.tinkers) |*tinker| {
        if (ray.IsKeyPressed(@as(c_int, tinker.key))) {
            tinker.enabled = !tinker.enabled;
            if (state.ipc_client) |c| c.toggleTinker(tinker.id);
        }
    }
    
    // Window dragging
    if (ray.IsMouseButtonDown(ray.MOUSE_BUTTON_LEFT)) {
        const mouse_y = ray.GetMouseY();
        if (mouse_y < 50) {
            const delta = ray.GetMouseDelta();
            const pos = ray.GetWindowPosition();
            ray.SetWindowPosition(
                @as(i32, @intFromFloat(pos.x + delta.x)),
                @as(i32, @intFromFloat(pos.y + delta.y)),
            );
        }
    }
}

fn drawTitleBar() void {
    // Background
    ray.DrawRectangle(0, 0, WINDOW_WIDTH, 50, Colors.mantle);
    ray.DrawRectangle(0, 48, WINDOW_WIDTH, 2, Colors.surface0);
    
    // Logo
    ray.DrawRectangleRounded(
        ray.Rectangle{ .x = 15, .y = 10, .width = 30, .height = 30 },
        0.3, 8, Colors.blue
    );
    ray.DrawText("S", 24, 13, 22, Colors.base);
    
    // Title
    ray.DrawText("STL-Next", 55, 12, FONT_MEDIUM, Colors.text);
    ray.DrawText("Wait Requester", 160, 15, FONT_SMALL, Colors.subtext);
    
    // Close button
    const close_rect = ray.Rectangle{ .x = WINDOW_WIDTH - 45, .y = 10, .width = 35, .height = 30 };
    const close_hover = ray.CheckCollisionPointRec(ray.GetMousePosition(), close_rect);
    
    if (close_hover) {
        ray.DrawRectangleRounded(close_rect, 0.3, 8, Colors.red);
        if (ray.IsMouseButtonPressed(ray.MOUSE_BUTTON_LEFT)) {
            state.cancelled = true;
        }
    }
    ray.DrawText("X", WINDOW_WIDTH - 35, 13, FONT_MEDIUM, if (close_hover) Colors.base else Colors.subtext);
}

fn drawGameSection() void {
    const y: i32 = 65;
    
    // Section label
    ray.DrawText("GAME", 25, y, FONT_TINY, Colors.muted);
    
    // Game name - large and prominent
    var name_buf: [256:0]u8 = undefined;
    const game_name = state.getGameName();
    const len = @min(game_name.len, name_buf.len - 1);
    @memcpy(name_buf[0..len], game_name[0..len]);
    name_buf[len] = 0;
    ray.DrawText(&name_buf, 25, y + 18, FONT_TITLE, Colors.blue);
    
    // AppID
    var id_buf: [64:0]u8 = undefined;
    _ = std.fmt.bufPrintZ(&id_buf, "Steam AppID: {d}", .{state.app_id}) catch {};
    ray.DrawText(&id_buf, 25, y + 58, FONT_SMALL, Colors.subtext);
}

fn drawCountdownSection() void {
    const y: i32 = 150;
    const bar_height: i32 = 45;
    
    // Section label
    ray.DrawText("COUNTDOWN", 25, y, FONT_TINY, Colors.muted);
    
    // Status text above bar
    var status_buf: [64:0]u8 = undefined;
    const countdown_int: u32 = @intFromFloat(@ceil(state.countdown));
    const status_text = if (state.paused) 
        "PAUSED - Press SPACE to resume"
    else if (countdown_int == 0)
        "Launching now..."
    else 
        "Game will launch in:";
    ray.DrawText(status_text, 25, y + 18, FONT_SMALL, if (state.paused) Colors.yellow else Colors.text);
    
    // Large countdown number
    _ = std.fmt.bufPrintZ(&status_buf, "{d}", .{countdown_int}) catch {};
    ray.DrawText(&status_buf, WINDOW_WIDTH - 80, y + 10, FONT_TITLE + 10, 
        if (state.paused) Colors.yellow else if (countdown_int <= 3) Colors.red else Colors.green);
    ray.DrawText("sec", WINDOW_WIDTH - 80, y + 55, FONT_TINY, Colors.muted);
    
    // Progress bar
    const bar_y = y + 45;
    const bar_rect = ray.Rectangle{
        .x = 25,
        .y = @floatFromInt(bar_y),
        .width = WINDOW_WIDTH - 130,
        .height = bar_height,
    };
    ray.DrawRectangleRounded(bar_rect, 0.2, 8, Colors.surface0);
    
    // Fill
    const progress = if (state.countdown_max > 0) state.countdown / state.countdown_max else 0;
    const fill_width = @as(f32, @floatFromInt(WINDOW_WIDTH - 138)) * progress;
    const fill_color = if (state.paused) Colors.yellow else if (progress < 0.3) Colors.red else Colors.green;
    
    const fill_rect = ray.Rectangle{
        .x = 29,
        .y = @floatFromInt(bar_y + 4),
        .width = fill_width,
        .height = bar_height - 8,
    };
    ray.DrawRectangleRounded(fill_rect, 0.2, 8, fill_color);
    
    // Hint below bar
    ray.DrawText("Press TAB to skip countdown, or SPACE to pause", 25, bar_y + bar_height + 8, FONT_TINY, Colors.muted);
}

fn drawTinkersSection() void {
    const y: i32 = 265;
    const col_width: i32 = 215;
    const row_height: i32 = 50;
    
    // Section label with help hint
    ray.DrawText("TINKERS", 25, y, FONT_TINY, Colors.muted);
    ray.DrawText("(hover for info, click or press key to toggle)", 90, y, FONT_TINY, Colors.muted);
    
    // Draw tinkers in 3 columns
    for (&state.tinkers, 0..) |*tinker, i| {
        const col: i32 = @intCast(i % 3);
        const row: i32 = @intCast(i / 3);
        const x = 25 + col * (col_width + 10);
        const ty = y + 22 + row * row_height;
        
        // Button rectangle
        const rect = ray.Rectangle{
            .x = @floatFromInt(x),
            .y = @floatFromInt(ty),
            .width = col_width,
            .height = row_height - 6,
        };
        
        const hover = ray.CheckCollisionPointRec(ray.GetMousePosition(), rect);
        
        // Background
        const bg = if (tinker.enabled)
            (if (hover) Colors.surface2 else Colors.surface1)
        else
            (if (hover) Colors.surface1 else Colors.surface0);
        ray.DrawRectangleRounded(rect, 0.2, 8, bg);
        
        // Left accent bar when enabled
        if (tinker.enabled) {
            const accent_rect = ray.Rectangle{
                .x = @floatFromInt(x + 3),
                .y = @floatFromInt(ty + 6),
                .width = 4,
                .height = row_height - 18,
            };
            ray.DrawRectangleRounded(accent_rect, 0.5, 4, tinker.color);
        }
        
        // Checkbox
        const check_text = if (tinker.enabled) "[ON]" else "[  ]";
        ray.DrawText(check_text, x + 14, ty + 12, FONT_SMALL, if (tinker.enabled) tinker.color else Colors.muted);
        
        // Name and key hint
        var label_buf: [64:0]u8 = undefined;
        _ = std.fmt.bufPrintZ(&label_buf, "{s}", .{tinker.name}) catch {};
        ray.DrawText(&label_buf, x + 70, ty + 8, FONT_SMALL, Colors.text);
        
        var key_buf: [8:0]u8 = undefined;
        _ = std.fmt.bufPrintZ(&key_buf, "[{c}]", .{tinker.key}) catch {};
        ray.DrawText(&key_buf, x + 70, ty + 27, FONT_TINY, Colors.muted);
        
        // Tooltip on hover
        if (hover) {
            state.hover_timer += ray.GetFrameTime();
            if (state.hover_timer > 0.3) {
                state.showTooltip(tinker.tooltip, ray.GetMouseX() + 15, ray.GetMouseY() + 15);
            }
            
            // Click to toggle
            if (ray.IsMouseButtonPressed(ray.MOUSE_BUTTON_LEFT)) {
                tinker.enabled = !tinker.enabled;
                if (state.ipc_client) |c| c.toggleTinker(tinker.id);
            }
        }
    }
}

fn drawActionsSection() void {
    const y: i32 = 385;
    const btn_width: i32 = 200;
    const btn_height: i32 = 55;
    const spacing: i32 = 20;
    
    // Section label
    ray.DrawText("ACTIONS", 25, y, FONT_TINY, Colors.muted);
    
    // Center buttons
    const total_width = btn_width * 3 + spacing * 2;
    const start_x = @divTrunc(WINDOW_WIDTH - total_width, 2);
    const btn_y = y + 20;
    
    // Launch button
    {
        const rect = ray.Rectangle{
            .x = @floatFromInt(start_x),
            .y = @floatFromInt(btn_y),
            .width = btn_width,
            .height = btn_height,
        };
        const hover = ray.CheckCollisionPointRec(ray.GetMousePosition(), rect);
        
        ray.DrawRectangleRounded(rect, 0.2, 8, if (hover) Colors.green else Colors.surface1);
        ray.DrawRectangleRoundedLinesEx(rect, 0.2, 8, 2, Colors.green);
        
        ray.DrawText("LAUNCH NOW", start_x + 30, btn_y + 10, FONT_MEDIUM, if (hover) Colors.base else Colors.green);
        ray.DrawText("Enter or L", start_x + 60, btn_y + 35, FONT_TINY, if (hover) Colors.base else Colors.muted);
        
        if (hover) {
            state.showTooltip("Start the game immediately", ray.GetMouseX() + 15, ray.GetMouseY() - 30);
            if (ray.IsMouseButtonPressed(ray.MOUSE_BUTTON_LEFT)) {
                state.launched = true;
                if (state.ipc_client) |c| c.proceed();
            }
        }
    }
    
    // Pause/Resume button
    {
        const rect = ray.Rectangle{
            .x = @floatFromInt(start_x + btn_width + spacing),
            .y = @floatFromInt(btn_y),
            .width = btn_width,
            .height = btn_height,
        };
        const hover = ray.CheckCollisionPointRec(ray.GetMousePosition(), rect);
        
        const btn_color = if (state.paused) Colors.green else Colors.yellow;
        ray.DrawRectangleRounded(rect, 0.2, 8, if (hover) btn_color else Colors.surface1);
        ray.DrawRectangleRoundedLinesEx(rect, 0.2, 8, 2, btn_color);
        
        const btn_text = if (state.paused) "RESUME" else "PAUSE";
        const text_width = ray.MeasureText(btn_text, FONT_MEDIUM);
        ray.DrawText(btn_text, start_x + btn_width + spacing + @divTrunc(btn_width - text_width, 2), btn_y + 10, FONT_MEDIUM, if (hover) Colors.base else btn_color);
        ray.DrawText("Space or P", start_x + btn_width + spacing + 55, btn_y + 35, FONT_TINY, if (hover) Colors.base else Colors.muted);
        
        if (hover) {
            const tip = if (state.paused) "Resume the countdown" else "Pause the countdown";
            state.showTooltip(tip, ray.GetMouseX() + 15, ray.GetMouseY() - 30);
            if (ray.IsMouseButtonPressed(ray.MOUSE_BUTTON_LEFT)) {
                state.paused = !state.paused;
                if (state.ipc_client) |c| {
                    if (state.paused) c.pause() else c.resumeCountdown();
                }
            }
        }
    }
    
    // Cancel button
    {
        const rect = ray.Rectangle{
            .x = @floatFromInt(start_x + (btn_width + spacing) * 2),
            .y = @floatFromInt(btn_y),
            .width = btn_width,
            .height = btn_height,
        };
        const hover = ray.CheckCollisionPointRec(ray.GetMousePosition(), rect);
        
        ray.DrawRectangleRounded(rect, 0.2, 8, if (hover) Colors.red else Colors.surface1);
        ray.DrawRectangleRoundedLinesEx(rect, 0.2, 8, 2, Colors.red);
        
        ray.DrawText("CANCEL", start_x + (btn_width + spacing) * 2 + 55, btn_y + 10, FONT_MEDIUM, if (hover) Colors.base else Colors.red);
        ray.DrawText("Esc or Q", start_x + (btn_width + spacing) * 2 + 60, btn_y + 35, FONT_TINY, if (hover) Colors.base else Colors.muted);
        
        if (hover) {
            state.showTooltip("Cancel and don't launch the game", ray.GetMouseX() + 15, ray.GetMouseY() - 30);
            if (ray.IsMouseButtonPressed(ray.MOUSE_BUTTON_LEFT)) {
                state.cancelled = true;
                if (state.ipc_client) |c| c.abort();
            }
        }
    }
}

fn drawStatusBar() void {
    const y = WINDOW_HEIGHT - 30;
    
    // Background
    ray.DrawRectangle(0, y, WINDOW_WIDTH, 30, Colors.mantle);
    ray.DrawRectangle(0, y, WINDOW_WIDTH, 1, Colors.surface0);
    
    // Connection status
    const status_icon = if (state.connected_to_daemon) "[*]" else "[-]";
    const status_text = if (state.connected_to_daemon) "Connected to daemon" else "Standalone mode";
    const status_color = if (state.connected_to_daemon) Colors.green else Colors.muted;
    ray.DrawText(status_icon, 15, y + 8, FONT_TINY, status_color);
    ray.DrawText(status_text, 40, y + 8, FONT_TINY, status_color);
    
    // Version
    ray.DrawText("STL-Next v0.5.3", WINDOW_WIDTH - 120, y + 8, FONT_TINY, Colors.muted);
}

fn drawTooltip() void {
    if (!state.tooltip.visible) return;
    
    const text = state.tooltip.text;
    const text_len = @as(c_int, @intCast(text.len));
    _ = text_len;
    
    // Measure text
    var text_buf: [256:0]u8 = undefined;
    const len = @min(text.len, text_buf.len - 1);
    @memcpy(text_buf[0..len], text[0..len]);
    text_buf[len] = 0;
    
    const text_width = ray.MeasureText(&text_buf, FONT_SMALL);
    const padding: i32 = 12;
    const width = text_width + padding * 2;
    const height: i32 = 35;
    
    // Ensure tooltip stays on screen
    var x = state.tooltip.x;
    var y = state.tooltip.y;
    if (x + width > WINDOW_WIDTH - 10) x = WINDOW_WIDTH - width - 10;
    if (y + height > WINDOW_HEIGHT - 10) y = state.tooltip.y - height - 20;
    if (x < 10) x = 10;
    if (y < 10) y = 10;
    
    // Draw tooltip box
    const rect = ray.Rectangle{
        .x = @floatFromInt(x),
        .y = @floatFromInt(y),
        .width = @floatFromInt(width),
        .height = height,
    };
    ray.DrawRectangleRounded(rect, 0.2, 8, Colors.tooltip_bg);
    ray.DrawRectangleRoundedLinesEx(rect, 0.2, 8, 1, Colors.tooltip_border);
    
    // Draw text
    ray.DrawText(&text_buf, x + padding, y + 8, FONT_SMALL, Colors.text);
    
    // Clear tooltip if mouse moved significantly
    const mouse = ray.GetMousePosition();
    const dx = @abs(mouse.x - @as(f32, @floatFromInt(state.tooltip.x - 15)));
    const dy = @abs(mouse.y - @as(f32, @floatFromInt(state.tooltip.y - 15)));
    if (dx > 100 or dy > 100) {
        state.hideTooltip();
    }
}

fn outputResult() void {
    const stdout_file = std.fs.File{ .handle = std.posix.STDOUT_FILENO };
    var buf: [256]u8 = undefined;
    
    if (state.launched) {
        const launch_msg = std.fmt.bufPrint(&buf, "LAUNCH:{d}\n", .{state.app_id}) catch "LAUNCH:0\n";
        stdout_file.writeAll(launch_msg) catch {};
        
        // Output enabled tinkers
        for (state.tinkers) |tinker| {
            if (tinker.enabled) {
                const tinker_msg = std.fmt.bufPrint(&buf, "TINKER:{s}\n", .{tinker.id}) catch continue;
                stdout_file.writeAll(tinker_msg) catch {};
            }
        }
    } else {
        stdout_file.writeAll("CANCELLED\n") catch {};
    }
}
