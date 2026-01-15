const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Build options
    const build_gui = b.option(bool, "gui", "Build with Raylib GUI (requires raylib)") orelse false;

    // Main CLI executable
    const exe = b.addExecutable(.{
        .name = "stl-next",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    
    exe.linkLibC();
    b.installArtifact(exe);

    // GUI executable (optional, requires raylib)
    if (build_gui) {
        const gui_exe = b.addExecutable(.{
            .name = "stl-next-gui",
            .root_module = b.createModule(.{
                .root_source_file = b.path("src/gui/main.zig"),
                .target = target,
                .optimize = optimize,
            }),
        });
        
        gui_exe.linkLibC();
        gui_exe.linkSystemLibrary("raylib");
        gui_exe.linkSystemLibrary("GL");
        gui_exe.linkSystemLibrary("m");
        gui_exe.linkSystemLibrary("pthread");
        gui_exe.linkSystemLibrary("dl");
        gui_exe.linkSystemLibrary("rt");
        gui_exe.linkSystemLibrary("X11");
        
        b.installArtifact(gui_exe);
        
        // Run GUI command
        const run_gui = b.addRunArtifact(gui_exe);
        run_gui.step.dependOn(b.getInstallStep());
        if (b.args) |args| {
            run_gui.addArgs(args);
        }
        
        const run_gui_step = b.step("run-gui", "Run STL-Next GUI");
        run_gui_step.dependOn(&run_gui.step);
    }

    // Run command
    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }
    
    const run_step = b.step("run", "Run STL-Next CLI");
    run_step.dependOn(&run_cmd.step);

    // Tests
    const main_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    
    const run_main_tests = b.addRunArtifact(main_tests);
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_main_tests.step);

    // Release build
    const release_exe = b.addExecutable(.{
        .name = "stl-next",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = .ReleaseFast,
        }),
    });
    release_exe.linkLibC();
    
    const release_step = b.step("release", "Build optimized release binary");
    const release_install = b.addInstallArtifact(release_exe, .{});
    release_step.dependOn(&release_install.step);
}
