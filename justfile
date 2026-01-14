# STL-Next Development Tasks
# https://github.com/casey/just

# Default recipe: show help
default:
    @just --list

# ═══════════════════════════════════════════════════════════════════════════════
# BUILD
# ═══════════════════════════════════════════════════════════════════════════════

# Build debug version
build:
    zig build

# Build optimized release
release:
    zig build release

# Clean build artifacts
clean:
    rm -rf zig-out .zig-cache

# ═══════════════════════════════════════════════════════════════════════════════
# TEST
# ═══════════════════════════════════════════════════════════════════════════════

# Run all tests
test:
    zig build test

# Run tests with verbose output
test-verbose:
    zig build test -- --verbose

# Run specific test file
test-file FILE:
    zig test src/{{FILE}}

# ═══════════════════════════════════════════════════════════════════════════════
# RUN
# ═══════════════════════════════════════════════════════════════════════════════

# Build and run
run *ARGS:
    zig build run -- {{ARGS}}

# Run with Stardew Valley
stardew:
    zig build run -- 413150

# Run info command
info APPID:
    zig build run -- info {{APPID}}

# List installed games
list-games:
    zig build run -- list-games

# ═══════════════════════════════════════════════════════════════════════════════
# DEVELOPMENT
# ═══════════════════════════════════════════════════════════════════════════════

# Watch for changes and rebuild
watch:
    watchexec -e zig -- zig build

# Watch and run tests
watch-test:
    watchexec -e zig -- zig build test

# Generate documentation
docs:
    zig build docs
    @echo "Documentation generated in zig-out/docs/"

# Format all Zig files
fmt:
    zig fmt src/

# Check formatting without modifying
fmt-check:
    zig fmt --check src/

# ═══════════════════════════════════════════════════════════════════════════════
# BENCHMARK
# ═══════════════════════════════════════════════════════════════════════════════

# Run benchmarks
bench:
    zig build bench

# Benchmark VDF parsing
bench-vdf:
    hyperfine --warmup 3 'zig-out/bin/stl-next list-games'

# ═══════════════════════════════════════════════════════════════════════════════
# RELEASE
# ═══════════════════════════════════════════════════════════════════════════════

# Build release and check size
release-info: release
    @echo "Binary size:"
    @ls -lh zig-out/bin/stl-next
    @echo ""
    @echo "Dependencies:"
    @ldd zig-out/bin/stl-next || echo "(static binary)"

# Create tarball for distribution
dist: release
    mkdir -p dist
    tar -czvf dist/stl-next-$(git describe --tags --always).tar.gz \
        -C zig-out/bin stl-next

# ═══════════════════════════════════════════════════════════════════════════════
# NIX
# ═══════════════════════════════════════════════════════════════════════════════

# Build with Nix
nix-build:
    nix build

# Run Nix checks
nix-check:
    nix flake check

# Update flake inputs
nix-update:
    nix flake update

# Enter development shell
dev:
    nix develop

