const std = @import("std");
const fs = std.fs;
const json = std.json;

// Import tinker configs (Phase 4.5)
const winetricks = @import("../tinkers/winetricks.zig");
const customcmd = @import("../tinkers/customcmd.zig");

// ═══════════════════════════════════════════════════════════════════════════════
// CONFIG: Game Configuration Management (Phase 6 - Full Featured)
// ═══════════════════════════════════════════════════════════════════════════════
//
// Uses proper std.json parsing instead of string searching.
// Configs are passed through Context, not global state.
//
// Phase 4.5 additions:
//   - Winetricks configuration
//   - Custom commands (pre/post launch)
//   - SteamGridDB settings
//
// Phase 6 additions:
//   - ReShade (shader injection)
//   - vkBasalt (Vulkan post-processing)
//   - SpecialK (HDR, frame pacing)
//   - LatencyFleX (low-latency gaming)
//   - MultiApp (helper app launcher)
//   - Proton Wayland toggle
//   - GPU device selection
//
// ═══════════════════════════════════════════════════════════════════════════════

/// MangoHud configuration
pub const MangoHudConfig = struct {
    enabled: bool = false,
    show_fps: bool = true,
    show_frametime: bool = true,
    show_cpu: bool = true,
    show_gpu: bool = true,
    show_vram: bool = false,
    show_ram: bool = false,
    show_cpu_temp: bool = false,
    show_gpu_temp: bool = true,
    position: []const u8 = "top-left",
    font_size: u8 = 24,
};

/// Gamescope configuration
pub const GamescopeConfig = struct {
    enabled: bool = false,
    width: u16 = 0,
    height: u16 = 0,
    internal_width: u16 = 0,
    internal_height: u16 = 0,
    fullscreen: bool = true,
    borderless: bool = false,
    fsr: bool = false,
    fsr_sharpness: u8 = 5,
    fps_limit: u16 = 0,
};

/// GameMode configuration
pub const GameModeConfig = struct {
    enabled: bool = false,
    renice: i8 = 0,
};

/// Winetricks configuration (re-exported from tinker)
pub const WinetricksConfig = winetricks.WinetricksConfig;

/// Custom commands configuration (re-exported from tinker)
pub const CustomCommandsConfig = customcmd.CustomCommandsConfig;

/// SteamGridDB configuration
pub const SteamGridDBConfig = struct {
    /// Enable automatic artwork fetching
    enabled: bool = false,
    /// Prefer animated images
    prefer_animated: bool = false,
    /// Preferred grid style
    grid_style: []const u8 = "alternate",
    /// Preferred hero style
    hero_style: []const u8 = "blurred",
    /// Download on first launch
    auto_download: bool = true,
    /// SteamGridDB game ID (for non-Steam games)
    game_id: ?u32 = null,
};

// Phase 6 Configuration Types (defined inline to avoid circular imports)

/// ReShade configuration
pub const ReshadeConfig = struct {
    enabled: bool = false,
    renderer: ?ReshadeRenderer = null,
    preset: ?[]const u8 = null,
    shader_sources: []const []const u8 = &.{},
    performance_mode: bool = false,
    show_fps: bool = false,
    show_clock: bool = false,
    screenshot_path: ?[]const u8 = null,
};

pub const ReshadeRenderer = enum {
    dx9,
    dx10,
    dx11,
    dx12,
    opengl,
    vulkan,
    unknown,
};

/// vkBasalt configuration
pub const VkbasaltConfig = struct {
    enabled: bool = false,
    effects: []const VkbasaltEffect = &.{.cas},
    cas_sharpness: f32 = 0.4,
    fxaa_quality: u8 = 3,
    smaa_threshold: f32 = 0.05,
    deband_range: u8 = 16,
    lut_file: ?[]const u8 = null,
    custom_effects: []const []const u8 = &.{},
    toggle_key: ?[]const u8 = null,
};

pub const VkbasaltEffect = enum {
    cas,
    fxaa,
    smaa,
    deband,
    lut,

    pub fn toString(self: VkbasaltEffect) []const u8 {
        return switch (self) {
            .cas => "cas",
            .fxaa => "fxaa",
            .smaa => "smaa",
            .deband => "deband",
            .lut => "lut",
        };
    }
};

/// SpecialK configuration
pub const SpecialkConfig = struct {
    enabled: bool = false,
    features: []const SpecialkFeature = &.{},
    target_fps: ?u32 = null,
    hdr_brightness: f32 = 1.0,
    hdr_peak: f32 = 1000.0,
    low_latency: bool = true,
    flip_model: bool = true,
    texture_cache: bool = false,
    injection_delay_ms: u32 = 0,
};

pub const SpecialkFeature = enum {
    hdr,
    framerate_limit,
    texture_mod,
    input_fix,
    overlay_fix,
    vsync_fix,
};

/// LatencyFleX configuration
pub const LatencyflexConfig = struct {
    enabled: bool = false,
    mode: LatencyflexMode = .auto,
    max_fps: ?u32 = null,
    wait_target_us: u32 = 0,
    allow_oversleep: bool = true,
};

pub const LatencyflexMode = enum {
    v1,
    v2,
    auto,
};

/// Multi-app launcher configuration
pub const MultiappConfig = struct {
    enabled: bool = false,
    apps: []const HelperApp = &.{},
    global_delay_ms: u32 = 500,
    kill_timeout_ms: u32 = 5000,
};

pub const HelperApp = struct {
    name: []const u8,
    command: []const u8,
    args: []const []const u8 = &.{},
    working_dir: ?[]const u8 = null,
    timing: AppLaunchTiming = .before_game,
    close_policy: AppClosePolicy = .on_game_exit,
    delay_ms: u32 = 0,
    minimize: bool = false,
};

pub const AppLaunchTiming = enum {
    before_game,
    with_game,
    after_game,
};

pub const AppClosePolicy = enum {
    on_game_exit,
    leave_running,
    ask_user,
};

/// Boxtron/Roberta (DOSBox/ScummVM) configuration
pub const BoxtronConfig = struct {
    /// Use Boxtron for DOS games
    boxtron_enabled: bool = false,
    /// Use Roberta for ScummVM games
    roberta_enabled: bool = false,
    /// Custom DOSBox config file
    dosbox_config: ?[]const u8 = null,
    /// DOSBox cycles (CPU speed)
    cycles: ?u32 = null,
    /// DOSBox fullscreen mode
    fullscreen: bool = true,
    /// DOSBox aspect correction
    aspect_correction: bool = true,
    /// DOSBox scaler
    scaler: BoxtronScaler = .normal2x,

    pub const BoxtronScaler = enum {
        none,
        normal2x,
        normal3x,
        hq2x,
        hq3x,
    };
};

/// OBS Studio capture integration
pub const ObsConfig = struct {
    /// Enable OBS integration
    enabled: bool = false,
    /// Auto-start recording when game launches
    auto_record: bool = false,
    /// Auto-start streaming when game launches
    auto_stream: bool = false,
    /// Switch to a specific scene for this game
    game_scene: ?[]const u8 = null,
    /// OBS websocket port
    websocket_port: u16 = 4455,
    /// Delay before starting recording (ms)
    start_delay_ms: u32 = 2000,
    /// Stop recording when game exits
    stop_on_exit: bool = true,
    /// Use replay buffer instead of recording
    use_replay_buffer: bool = false,
};

/// DLSS Tweaks configuration
pub const DlssConfig = struct {
    /// Enable DLSS tweaks
    enabled: bool = false,
    /// DLSS quality preset
    preset: DlssPreset = .quality,
    /// Enable DLSS Frame Generation (RTX 40+ series)
    frame_generation: bool = false,
    /// Enable Reflex low latency
    reflex: DlssReflexMode = .on,
    /// Show DLSS indicator overlay
    indicator: bool = false,
    /// Custom DLSS DLL path (for DLL swapping)
    custom_dll: ?[]const u8 = null,
    /// DLSS sharpening (0.0-1.0)
    sharpening: f32 = 0.5,
    /// Ray reconstruction (RTX 40+ series)
    ray_reconstruction: bool = false,

    pub const DlssPreset = enum {
        off,
        ultra_performance,
        performance,
        balanced,
        quality,
        ultra_quality,
        dlaa,
    };

    pub const DlssReflexMode = enum {
        off,
        on,
        on_boost,
    };
};

/// OptiScaler configuration (universal upscaler)
pub const OptiScalerConfig = struct {
    /// Enable OptiScaler
    enabled: bool = false,
    /// Upscaler backend to use
    backend: OptiScalerBackend = .auto,
    /// Enable frame generation
    frame_generation: bool = true,
    /// FSR quality preset
    fsr_quality: FsrQuality = .quality,
    /// Sharpening amount (0.0-1.0)
    sharpening: f32 = 0.5,
    /// Anti-lag mode
    anti_lag: bool = true,
    /// Override game's native upscaler
    override_native: bool = true,
    /// Enable debug overlay
    debug_overlay: bool = false,

    pub const OptiScalerBackend = enum {
        fsr31,
        xess,
        dlss,
        auto,
    };

    pub const FsrQuality = enum {
        ultra_performance,
        performance,
        balanced,
        quality,
        ultra_quality,
    };
};

/// Proton/Wine advanced configuration
pub const ProtonAdvancedConfig = struct {
    /// Enable Proton's native Wayland support
    enable_wayland: bool = false,
    /// Enable NVIDIA DLSS
    enable_nvapi: bool = false,
    /// Enable Ray Tracing support
    enable_rtx: bool = false,
    /// Custom WINE prefix path (overrides default)
    wine_prefix: ?[]const u8 = null,
    /// DXVK async shader compilation
    dxvk_async: bool = true,
    /// VKD3D Ray Tracing
    vkd3d_rt: bool = false,
};

/// GPU/Display configuration
pub const GpuConfig = struct {
    /// Vulkan device selection (for multi-GPU systems)
    /// Use "1002:73bf" format for vendor:device
    vk_device: ?[]const u8 = null,
    /// Mesa Vulkan device index (0, 1, etc.)
    mesa_device_index: ?u8 = null,
    /// Force specific GPU for PRIME render offload
    prime_offload: bool = false,
    /// DRI device path override
    dri_device: ?[]const u8 = null,
};

/// Complete game configuration
/// Launch profile for per-game GPU/monitor/settings presets (Phase 8)
/// Allows multiple configurations per game without editing Steam launch options
pub const LaunchProfile = struct {
    /// Profile name (e.g., "Arc A770 - Main Monitor", "RTX 2080 - 4K TV")
    name: []const u8 = "Default",

    /// Profile description
    description: ?[]const u8 = null,

    /// GPU preference for this profile
    gpu_preference: GpuPreference = .auto,

    /// Specific GPU index (when gpu_preference is .specific)
    gpu_index: ?usize = null,

    /// Target monitor name (e.g., "DP-1", "HDMI-A-1") - for suggestions
    target_monitor: ?[]const u8 = null,

    /// Override launch options (appended to base config)
    extra_launch_options: ?[]const u8 = null,

    /// Override resolution (for this profile only)
    resolution_override: ?Resolution = null,

    /// Override Proton version
    proton_override: ?[]const u8 = null,

    /// Enable specific features for this profile
    enable_mangohud: ?bool = null,
    enable_gamescope: ?bool = null,
    enable_gamemode: ?bool = null,

    /// When true, add this profile as a non-Steam game shortcut
    create_steam_shortcut: bool = false,

    /// Steam shortcut ID (if created)
    steam_shortcut_id: ?u32 = null,
};

/// GPU preference - re-export from dbus module for consistency
pub const GpuPreference = @import("../dbus/mod.zig").GpuPreference;

/// Resolution override
pub const Resolution = struct {
    width: u32,
    height: u32,
    refresh_hz: ?u32 = null,
};

pub const GameConfig = struct {
    app_id: u32,
    name: []const u8 = "Unknown Game",
    use_native: bool = false,
    proton_version: ?[]const u8 = null,
    launch_options: ?[]const u8 = null,

    // === PROFILES (Phase 8) ===
    /// Active profile name (index into profiles array)
    active_profile: []const u8 = "Default",

    /// Available launch profiles (GPU/monitor/settings presets)
    /// First profile is always "Default" with base settings
    profiles: []const LaunchProfile = &[_]LaunchProfile{.{}},

    // Core tinker configurations (Phase 3)
    mangohud: MangoHudConfig = .{},
    gamescope: GamescopeConfig = .{},
    gamemode: GameModeConfig = .{},

    // Extended tinker configurations (Phase 4.5)
    winetricks: WinetricksConfig = .{},
    custom_commands: CustomCommandsConfig = .{},

    // Advanced tinker configurations (Phase 6)
    reshade: ReshadeConfig = .{},
    vkbasalt: VkbasaltConfig = .{},
    specialk: SpecialkConfig = .{},
    latencyflex: LatencyflexConfig = .{},
    multiapp: MultiappConfig = .{},
    boxtron: BoxtronConfig = .{},
    obs: ObsConfig = .{},
    dlss: DlssConfig = .{},
    optiscaler: OptiScalerConfig = .{},

    // Proton/Wine advanced settings
    proton_advanced: ProtonAdvancedConfig = .{},

    // GPU configuration (base/fallback)
    gpu: GpuConfig = .{},

    // Artwork configuration
    steamgriddb: SteamGridDBConfig = .{},

    /// Whether this config was loaded from disk (vs default) - determines if we need to free strings
    _loaded_from_disk: bool = false,
    /// Allocator used when loading (null for defaults)
    _allocator: ?std.mem.Allocator = null,

    pub fn defaults(app_id: u32) GameConfig {
        return .{ .app_id = app_id };
    }

    /// Clean up allocated memory (call when done with a loaded config)
    pub fn deinit(self: *GameConfig) void {
        const allocator = self._allocator orelse return;
        if (!self._loaded_from_disk) return;

        // Free allocated strings - all strings in a loaded config are heap-allocated
        // because loadGameConfig uses allocator.dupe() for all string values
        allocator.free(self.active_profile);
        if (self.proton_version) |v| allocator.free(v);
        if (self.launch_options) |v| allocator.free(v);
        allocator.free(self.mangohud.position);

        // Free profiles array and profile strings
        // When loaded from disk, profiles is always a heap-allocated array
        for (self.profiles) |profile| {
            allocator.free(profile.name);
            if (profile.target_monitor) |m| allocator.free(m);
            if (profile.description) |d| allocator.free(d);
            if (profile.extra_launch_options) |o| allocator.free(o);
            if (profile.proton_override) |p| allocator.free(p);
        }
        if (self.profiles.len > 0) {
            allocator.free(self.profiles);
        }
    }

    /// Get the currently active profile
    pub fn getActiveProfile(self: *const GameConfig) ?*const LaunchProfile {
        for (self.profiles) |*profile| {
            if (std.mem.eql(u8, profile.name, self.active_profile)) {
                return profile;
            }
        }
        return if (self.profiles.len > 0) &self.profiles[0] else null;
    }

    /// Get a profile by name
    pub fn getProfile(self: *const GameConfig, name: []const u8) ?*const LaunchProfile {
        for (self.profiles) |*profile| {
            if (std.mem.eql(u8, profile.name, name)) {
                return profile;
            }
        }
        return null;
    }

    /// Add a new profile (allocates new profiles array)
    /// Note: This leaks the old profiles array in debug builds. For a CLI tool that
    /// exits immediately, this is acceptable. For long-running processes, consider
    /// tracking allocation status.
    pub fn addProfile(self: *GameConfig, allocator: std.mem.Allocator, profile: LaunchProfile) !void {
        // Check if profile already exists
        for (self.profiles) |existing| {
            if (std.mem.eql(u8, existing.name, profile.name)) {
                return error.ProfileExists;
            }
        }

        // Create new profiles array with the added profile
        const new_profiles = try allocator.alloc(LaunchProfile, self.profiles.len + 1);
        @memcpy(new_profiles[0..self.profiles.len], self.profiles);
        new_profiles[self.profiles.len] = profile;

        // Update profiles pointer
        self.profiles = new_profiles;
    }

    /// Remove a profile by name
    pub fn removeProfile(self: *GameConfig, allocator: std.mem.Allocator, name: []const u8) !void {
        if (std.mem.eql(u8, name, "Default")) {
            return error.CannotRemoveDefault;
        }

        // Find the profile index
        var found_idx: ?usize = null;
        for (self.profiles, 0..) |profile, i| {
            if (std.mem.eql(u8, profile.name, name)) {
                found_idx = i;
                break;
            }
        }

        const idx = found_idx orelse return error.ProfileNotFound;

        // Create new array without the removed profile
        if (self.profiles.len == 1) {
            return error.CannotRemoveLastProfile;
        }

        var new_profiles = try allocator.alloc(LaunchProfile, self.profiles.len - 1);
        var j: usize = 0;
        for (self.profiles, 0..) |profile, i| {
            if (i != idx) {
                new_profiles[j] = profile;
                j += 1;
            }
        }

        // If active profile was removed, switch to first
        if (std.mem.eql(u8, self.active_profile, name)) {
            self.active_profile = new_profiles[0].name;
        }

        self.profiles = new_profiles;
    }
};

/// Get the config directory path
pub fn getConfigDir(allocator: std.mem.Allocator) ![]const u8 {
    if (std.posix.getenv("STL_CONFIG_DIR")) |dir| {
        return allocator.dupe(u8, dir);
    }
    if (std.posix.getenv("XDG_CONFIG_HOME")) |xdg| {
        return std.fmt.allocPrint(allocator, "{s}/stl-next", .{xdg});
    }
    if (std.posix.getenv("HOME")) |home| {
        return std.fmt.allocPrint(allocator, "{s}/.config/stl-next", .{home});
    }
    return error.NoConfigDir;
}

/// Load game configuration from disk using proper JSON parsing
pub fn loadGameConfig(allocator: std.mem.Allocator, app_id: u32) !GameConfig {
    const config_dir = try getConfigDir(allocator);
    defer allocator.free(config_dir);

    const config_path = try std.fmt.allocPrint(
        allocator,
        "{s}/games/{d}.json",
        .{ config_dir, app_id },
    );
    defer allocator.free(config_path);

    const file = fs.openFileAbsolute(config_path, .{}) catch |err| {
        if (err == error.FileNotFound) {
            std.log.debug("Config: No config for AppID {d}, using defaults", .{app_id});
            return GameConfig.defaults(app_id);
        }
        return err;
    };
    defer file.close();

    const stat = try file.stat();
    if (stat.size > 1024 * 1024) {
        return error.ConfigFileTooLarge;
    }

    const content = try allocator.alloc(u8, stat.size);
    defer allocator.free(content);
    _ = try file.readAll(content);

    // Parse JSON properly
    var config = GameConfig.defaults(app_id);

    var parsed = json.parseFromSlice(json.Value, allocator, content, .{}) catch |err| {
        std.log.warn("Config: Failed to parse JSON for AppID {d}: {}", .{ app_id, err });
        return config;
    };
    defer parsed.deinit();

    const root = parsed.value;
    if (root != .object) {
        std.log.warn("Config: Root is not an object for AppID {d}", .{app_id});
        return config;
    }

    const obj = root.object;

    // Parse top-level fields
    if (obj.get("use_native")) |v| {
        if (v == .bool) config.use_native = v.bool;
    }
    if (obj.get("proton_version")) |v| {
        if (v == .string) config.proton_version = try allocator.dupe(u8, v.string);
    }
    if (obj.get("launch_options")) |v| {
        if (v == .string) config.launch_options = try allocator.dupe(u8, v.string);
    }

    // Parse MangoHud config
    if (obj.get("mangohud")) |mh| {
        if (mh == .object) {
            const mh_obj = mh.object;
            if (mh_obj.get("enabled")) |v| {
                if (v == .bool) config.mangohud.enabled = v.bool;
            }
            if (mh_obj.get("show_fps")) |v| {
                if (v == .bool) config.mangohud.show_fps = v.bool;
            }
            if (mh_obj.get("show_frametime")) |v| {
                if (v == .bool) config.mangohud.show_frametime = v.bool;
            }
            if (mh_obj.get("show_cpu")) |v| {
                if (v == .bool) config.mangohud.show_cpu = v.bool;
            }
            if (mh_obj.get("show_gpu")) |v| {
                if (v == .bool) config.mangohud.show_gpu = v.bool;
            }
            if (mh_obj.get("position")) |v| {
                if (v == .string) config.mangohud.position = try allocator.dupe(u8, v.string);
            }
            if (mh_obj.get("font_size")) |v| {
                if (v == .integer) config.mangohud.font_size = @intCast(v.integer);
            }
        }
    }

    // Parse Gamescope config
    if (obj.get("gamescope")) |gs| {
        if (gs == .object) {
            const gs_obj = gs.object;
            if (gs_obj.get("enabled")) |v| {
                if (v == .bool) config.gamescope.enabled = v.bool;
            }
            if (gs_obj.get("width")) |v| {
                if (v == .integer) config.gamescope.width = @intCast(v.integer);
            }
            if (gs_obj.get("height")) |v| {
                if (v == .integer) config.gamescope.height = @intCast(v.integer);
            }
            if (gs_obj.get("fullscreen")) |v| {
                if (v == .bool) config.gamescope.fullscreen = v.bool;
            }
            if (gs_obj.get("fsr")) |v| {
                if (v == .bool) config.gamescope.fsr = v.bool;
            }
            if (gs_obj.get("fps_limit")) |v| {
                if (v == .integer) config.gamescope.fps_limit = @intCast(v.integer);
            }
        }
    }

    // Parse GameMode config
    if (obj.get("gamemode")) |gm| {
        if (gm == .object) {
            const gm_obj = gm.object;
            if (gm_obj.get("enabled")) |v| {
                if (v == .bool) config.gamemode.enabled = v.bool;
            }
            if (gm_obj.get("renice")) |v| {
                if (v == .integer) config.gamemode.renice = @intCast(v.integer);
            }
        }
    }

    // Parse active_profile
    if (obj.get("active_profile")) |v| {
        if (v == .string) config.active_profile = try allocator.dupe(u8, v.string);
    }

    // Parse profiles array
    if (obj.get("profiles")) |profiles_val| {
        if (profiles_val == .array) {
            const profiles_array = profiles_val.array;
            var profiles_list = try allocator.alloc(LaunchProfile, profiles_array.items.len);

            for (profiles_array.items, 0..) |profile_val, i| {
                if (profile_val != .object) continue;
                const profile_obj = profile_val.object;

                var profile = LaunchProfile{
                    .name = "Unnamed",
                    .gpu_preference = .auto,
                    .gpu_index = null,
                    .target_monitor = null,
                    .resolution_override = null,
                    .enable_mangohud = null,
                    .enable_gamescope = null,
                    .enable_gamemode = null,
                    .create_steam_shortcut = false,
                };

                if (profile_obj.get("name")) |v| {
                    if (v == .string) profile.name = try allocator.dupe(u8, v.string);
                }
                if (profile_obj.get("gpu_preference")) |v| {
                    if (v == .string) {
                        const pref_str = v.string;
                        if (std.mem.eql(u8, pref_str, "nvidia")) {
                            profile.gpu_preference = .nvidia;
                        } else if (std.mem.eql(u8, pref_str, "amd")) {
                            profile.gpu_preference = .amd;
                        } else if (std.mem.eql(u8, pref_str, "intel_arc")) {
                            profile.gpu_preference = .intel_arc;
                        } else if (std.mem.eql(u8, pref_str, "integrated")) {
                            profile.gpu_preference = .integrated;
                        } else if (std.mem.eql(u8, pref_str, "discrete")) {
                            profile.gpu_preference = .discrete;
                        } else if (std.mem.eql(u8, pref_str, "specific")) {
                            profile.gpu_preference = .specific;
                        }
                    }
                }
                if (profile_obj.get("gpu_index")) |v| {
                    if (v == .integer) profile.gpu_index = @intCast(v.integer);
                }
                if (profile_obj.get("target_monitor")) |v| {
                    if (v == .string) profile.target_monitor = try allocator.dupe(u8, v.string);
                }

                // Parse resolution
                const res_width = profile_obj.get("resolution_width");
                const res_height = profile_obj.get("resolution_height");
                if (res_width != null and res_height != null) {
                    if (res_width.? == .integer and res_height.? == .integer) {
                        var res = Resolution{
                            .width = @intCast(res_width.?.integer),
                            .height = @intCast(res_height.?.integer),
                            .refresh_hz = null,
                        };
                        if (profile_obj.get("resolution_refresh_hz")) |v| {
                            if (v == .integer) res.refresh_hz = @intCast(v.integer);
                        }
                        profile.resolution_override = res;
                    }
                }

                if (profile_obj.get("enable_mangohud")) |v| {
                    if (v == .bool) profile.enable_mangohud = v.bool;
                }
                if (profile_obj.get("enable_gamescope")) |v| {
                    if (v == .bool) profile.enable_gamescope = v.bool;
                }
                if (profile_obj.get("enable_gamemode")) |v| {
                    if (v == .bool) profile.enable_gamemode = v.bool;
                }
                if (profile_obj.get("create_steam_shortcut")) |v| {
                    if (v == .bool) profile.create_steam_shortcut = v.bool;
                }

                profiles_list[i] = profile;
            }

            config.profiles = profiles_list;
        }
    }

    // Mark as loaded from disk so deinit knows to free
    config._loaded_from_disk = true;
    config._allocator = allocator;

    std.log.info("Config: Loaded for AppID {d}", .{app_id});
    return config;
}

/// Save game configuration to disk
pub fn saveGameConfig(allocator: std.mem.Allocator, config: *const GameConfig) !void {
    const config_dir = try getConfigDir(allocator);
    defer allocator.free(config_dir);

    const games_dir = try std.fmt.allocPrint(allocator, "{s}/games", .{config_dir});
    defer allocator.free(games_dir);

    // Ensure directories exist
    fs.makeDirAbsolute(config_dir) catch |err| {
        if (err != error.PathAlreadyExists) return err;
    };
    fs.makeDirAbsolute(games_dir) catch |err| {
        if (err != error.PathAlreadyExists) return err;
    };

    const config_path = try std.fmt.allocPrint(
        allocator,
        "{s}/{d}.json",
        .{ games_dir, config.app_id },
    );
    defer allocator.free(config_path);

    const file = try fs.createFileAbsolute(config_path, .{});
    defer file.close();

    // Zig 0.15.x: Use bufPrint + writeAll pattern
    var buf: [4096]u8 = undefined;

    try file.writeAll("{\n");
    try file.writeAll(try std.fmt.bufPrint(&buf, "  \"app_id\": {d},\n", .{config.app_id}));
    try file.writeAll(try std.fmt.bufPrint(&buf, "  \"use_native\": {s},\n", .{if (config.use_native) "true" else "false"}));

    // MangoHud
    try file.writeAll("  \"mangohud\": {\n");
    try file.writeAll(try std.fmt.bufPrint(&buf, "    \"enabled\": {s},\n", .{if (config.mangohud.enabled) "true" else "false"}));
    try file.writeAll(try std.fmt.bufPrint(&buf, "    \"show_fps\": {s},\n", .{if (config.mangohud.show_fps) "true" else "false"}));
    try file.writeAll(try std.fmt.bufPrint(&buf, "    \"position\": \"{s}\",\n", .{config.mangohud.position}));
    try file.writeAll(try std.fmt.bufPrint(&buf, "    \"font_size\": {d}\n", .{config.mangohud.font_size}));
    try file.writeAll("  },\n");

    // Gamescope
    try file.writeAll("  \"gamescope\": {\n");
    try file.writeAll(try std.fmt.bufPrint(&buf, "    \"enabled\": {s},\n", .{if (config.gamescope.enabled) "true" else "false"}));
    try file.writeAll(try std.fmt.bufPrint(&buf, "    \"width\": {d},\n", .{config.gamescope.width}));
    try file.writeAll(try std.fmt.bufPrint(&buf, "    \"height\": {d},\n", .{config.gamescope.height}));
    try file.writeAll(try std.fmt.bufPrint(&buf, "    \"fullscreen\": {s},\n", .{if (config.gamescope.fullscreen) "true" else "false"}));
    try file.writeAll(try std.fmt.bufPrint(&buf, "    \"fsr\": {s},\n", .{if (config.gamescope.fsr) "true" else "false"}));
    try file.writeAll(try std.fmt.bufPrint(&buf, "    \"fps_limit\": {d}\n", .{config.gamescope.fps_limit}));
    try file.writeAll("  },\n");

    // GameMode
    try file.writeAll("  \"gamemode\": {\n");
    try file.writeAll(try std.fmt.bufPrint(&buf, "    \"enabled\": {s},\n", .{if (config.gamemode.enabled) "true" else "false"}));
    try file.writeAll(try std.fmt.bufPrint(&buf, "    \"renice\": {d}\n", .{config.gamemode.renice}));
    try file.writeAll("  },\n");

    // Active profile
    try file.writeAll(try std.fmt.bufPrint(&buf, "  \"active_profile\": \"{s}\",\n", .{config.active_profile}));

    // Profiles array
    try file.writeAll("  \"profiles\": [\n");
    for (config.profiles, 0..) |profile, i| {
        try file.writeAll("    {\n");
        try file.writeAll(try std.fmt.bufPrint(&buf, "      \"name\": \"{s}\",\n", .{profile.name}));
        try file.writeAll(try std.fmt.bufPrint(&buf, "      \"gpu_preference\": \"{s}\",\n", .{@tagName(profile.gpu_preference)}));

        if (profile.gpu_index) |idx| {
            try file.writeAll(try std.fmt.bufPrint(&buf, "      \"gpu_index\": {d},\n", .{idx}));
        }
        if (profile.target_monitor) |mon| {
            try file.writeAll(try std.fmt.bufPrint(&buf, "      \"target_monitor\": \"{s}\",\n", .{mon}));
        }
        if (profile.resolution_override) |res| {
            try file.writeAll(try std.fmt.bufPrint(&buf, "      \"resolution_width\": {d},\n", .{res.width}));
            try file.writeAll(try std.fmt.bufPrint(&buf, "      \"resolution_height\": {d},\n", .{res.height}));
            if (res.refresh_hz) |hz| {
                try file.writeAll(try std.fmt.bufPrint(&buf, "      \"resolution_refresh_hz\": {d},\n", .{hz}));
            }
        }
        if (profile.enable_mangohud) |mh| {
            try file.writeAll(try std.fmt.bufPrint(&buf, "      \"enable_mangohud\": {s},\n", .{if (mh) "true" else "false"}));
        }
        if (profile.enable_gamescope) |gs| {
            try file.writeAll(try std.fmt.bufPrint(&buf, "      \"enable_gamescope\": {s},\n", .{if (gs) "true" else "false"}));
        }
        if (profile.enable_gamemode) |gm| {
            try file.writeAll(try std.fmt.bufPrint(&buf, "      \"enable_gamemode\": {s},\n", .{if (gm) "true" else "false"}));
        }
        try file.writeAll(try std.fmt.bufPrint(&buf, "      \"create_steam_shortcut\": {s}\n", .{if (profile.create_steam_shortcut) "true" else "false"}));

        if (i < config.profiles.len - 1) {
            try file.writeAll("    },\n");
        } else {
            try file.writeAll("    }\n");
        }
    }
    try file.writeAll("  ]\n");

    try file.writeAll("}\n");

    std.log.info("Config: Saved to {s}", .{config_path});
}

// ═══════════════════════════════════════════════════════════════════════════════
// TESTS
// ═══════════════════════════════════════════════════════════════════════════════

test "default config" {
    const config = GameConfig.defaults(413150);
    try std.testing.expectEqual(@as(u32, 413150), config.app_id);
    try std.testing.expect(!config.use_native);
    try std.testing.expect(!config.mangohud.enabled);
}

test "json parsing" {
    const test_json =
        \\{
        \\  "app_id": 413150,
        \\  "use_native": false,
        \\  "mangohud": {
        \\    "enabled": true,
        \\    "show_fps": true
        \\  }
        \\}
    ;

    var parsed = try json.parseFromSlice(json.Value, std.testing.allocator, test_json, .{});
    defer parsed.deinit();

    try std.testing.expect(parsed.value == .object);
    const obj = parsed.value.object;
    try std.testing.expectEqual(@as(i64, 413150), obj.get("app_id").?.integer);
}
