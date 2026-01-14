const std = @import("std");

// ═══════════════════════════════════════════════════════════════════════════════
// STL-NEXT BUILD CONFIGURATION (Zig 0.13.0)
// ═══════════════════════════════════════════════════════════════════════════════

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // ═════════════════════════════════════════════════════════════════════════════
    // MAIN EXECUTABLE
    // ═════════════════════════════════════════════════════════════════════════════

    const exe = b.addExecutable(.{
        .name = "stl-next",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    // Link libc for system calls
    exe.linkLibC();

    // Install the executable
    b.installArtifact(exe);

    // ═════════════════════════════════════════════════════════════════════════════
    // RUN COMMAND
    // ═════════════════════════════════════════════════════════════════════════════

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());

    // Pass arguments to the executable
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run stl-next");
    run_step.dependOn(&run_cmd.step);

    // ═════════════════════════════════════════════════════════════════════════════
    // UNIT TESTS
    // ═════════════════════════════════════════════════════════════════════════════

    // Main tests
    const main_tests = b.addTest(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    // VDF parser tests
    const vdf_tests = b.addTest(.{
        .root_source_file = b.path("src/engine/vdf.zig"),
        .target = target,
        .optimize = optimize,
    });

    // Config tests
    const config_tests = b.addTest(.{
        .root_source_file = b.path("src/core/config.zig"),
        .target = target,
        .optimize = optimize,
    });

    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&b.addRunArtifact(main_tests).step);
    test_step.dependOn(&b.addRunArtifact(vdf_tests).step);
    test_step.dependOn(&b.addRunArtifact(config_tests).step);

    // ═════════════════════════════════════════════════════════════════════════════
    // RELEASE BUILD
    // ═════════════════════════════════════════════════════════════════════════════

    const release = b.addExecutable(.{
        .name = "stl-next-release",
        .root_source_file = b.path("src/main.zig"),
        .target = b.resolveTargetQuery(.{
            .cpu_arch = .x86_64,
            .os_tag = .linux,
        }),
        .optimize = .ReleaseFast,
    });
    release.linkLibC();

    const release_step = b.step("release", "Build optimized release binary");
    release_step.dependOn(&b.addInstallArtifact(release, .{}).step);

    // ═════════════════════════════════════════════════════════════════════════════
    // BENCHMARKS
    // ═════════════════════════════════════════════════════════════════════════════

    const bench = b.addExecutable(.{
        .name = "stl-bench",
        .root_source_file = b.path("benches/main.zig"),
        .target = target,
        .optimize = .ReleaseFast,
    });

    const bench_step = b.step("bench", "Run benchmarks");
    bench_step.dependOn(&b.addRunArtifact(bench).step);
}
