{
  description = "STL-Next: Steam Tinker Launch - Next Generation (Zig Rewrite)";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";

    # Zig overlay for latest stable
    zig-overlay = {
      url = "github:mitchellh/zig-overlay";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Zls (Zig Language Server)
    zls = {
      url = "github:zigtools/zls";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, flake-utils, zig-overlay, zls }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs {
          inherit system;
          overlays = [ zig-overlay.overlays.default ];
        };

        # Use stable Zig 0.13.0
        zig = pkgs.zigpkgs."0.13.0";

        # C libraries for future interop
        buildInputs = with pkgs; [
          # Archive handling
          libarchive
          zstd
          lz4
          xz

          # LevelDB for Steam collections
          leveldb
          snappy

          # GUI (optional - for future Raylib integration)
          # raylib
          # libGL
          # xorg.libX11
          # xorg.libXcursor
          # xorg.libXrandr
          # xorg.libXinerama
          # xorg.libXi
        ];

        nativeBuildInputs = with pkgs; [
          pkg-config
        ];
      in
      {
        # ═══════════════════════════════════════════════════════════════════════════
        # DEVELOPMENT SHELL
        # ═══════════════════════════════════════════════════════════════════════════
        devShells.default = pkgs.mkShell {
          packages = with pkgs; [
            zig
            zls.packages.${system}.default

            # Build tools
            gnumake
            pkg-config

            # Testing & debugging
            gdb
            valgrind
            hyperfine # Benchmarking

            # Documentation
            graphviz # For module dependency graphs

            # Development utilities
            just # Task runner
            watchexec # File watcher for auto-rebuild
          ] ++ buildInputs;

          shellHook = ''
            echo "╔══════════════════════════════════════════╗"
            echo "║      STL-Next Development Shell          ║"
            echo "╠══════════════════════════════════════════╣"
            echo "║ zig version: $(zig version)             ║"
            echo "╚══════════════════════════════════════════╝"
            echo ""
            echo "Commands:"
            echo "  zig build         Build debug binary"
            echo "  zig build run     Build and run"
            echo "  zig build test    Run unit tests"
            echo "  zig build release Build optimized release"
            echo "  zig build docs    Generate documentation"
            echo ""
          '';

          # For C library linking
          LD_LIBRARY_PATH = pkgs.lib.makeLibraryPath buildInputs;
          PKG_CONFIG_PATH = "${pkgs.libarchive}/lib/pkgconfig:${pkgs.leveldb}/lib/pkgconfig";
        };

        # ═══════════════════════════════════════════════════════════════════════════
        # PACKAGES
        # ═══════════════════════════════════════════════════════════════════════════
        packages = {
          default = self.packages.${system}.stl-next;

          stl-next = pkgs.stdenv.mkDerivation {
            pname = "stl-next";
            version = "0.1.0";

            src = self;

            nativeBuildInputs = [ zig pkgs.pkg-config ];
            inherit buildInputs;

            # Zig build
            buildPhase = ''
              export ZIG_GLOBAL_CACHE_DIR="$TMPDIR/zig-cache"
              zig build -Doptimize=ReleaseFast --prefix $out
            '';

            installPhase = ''
              # Already installed by zig build --prefix
              :
            '';

            meta = with pkgs.lib; {
              description = "Steam Tinker Launch - Next Generation (Zig Rewrite)";
              homepage = "https://github.com/e421/stl-next";
              license = licenses.gpl3;
              platforms = platforms.linux;
              mainProgram = "stl-next";
            };
          };
        };

        # ═══════════════════════════════════════════════════════════════════════════
        # APPS
        # ═══════════════════════════════════════════════════════════════════════════
        apps = {
          default = self.apps.${system}.stl-next;

          stl-next = {
            type = "app";
            program = "${self.packages.${system}.stl-next}/bin/stl-next";
          };
        };

        # ═══════════════════════════════════════════════════════════════════════════
        # CHECKS
        # ═══════════════════════════════════════════════════════════════════════════
        checks = {
          # Unit tests
          test = pkgs.stdenv.mkDerivation {
            name = "stl-next-tests";
            src = self;
            nativeBuildInputs = [ zig pkgs.pkg-config ];
            inherit buildInputs;
            buildPhase = ''
              export ZIG_GLOBAL_CACHE_DIR="$TMPDIR/zig-cache"
              zig build test
            '';
            installPhase = "touch $out";
          };
        };
      });
}
