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

        # C libraries for interop
        buildInputs = with pkgs; [
          # Archive handling (for mod extraction)
          libarchive
          zstd
          lz4
          xz

          # LevelDB for Steam collections (Phase 2)
          leveldb
          snappy
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

            # C library headers
            leveldb.dev
            libarchive.dev

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
            echo "║           Phase 2: Binary VDF            ║"
            echo "╠══════════════════════════════════════════╣"
            echo "║ zig version: $(zig version)             ║"
            echo "╚══════════════════════════════════════════╝"
            echo ""
            echo "Commands:"
            echo "  zig build         Build debug binary"
            echo "  zig build run     Build and run"
            echo "  zig build test    Run unit tests"
            echo "  zig build release Build optimized release"
            echo ""
            echo "Phase 2 Features:"
            echo "  ✓ Binary VDF streaming parser"
            echo "  ✓ Fast AppID seeking (<10ms for 200MB)"
            echo "  ✓ LevelDB collections support"
            echo "  ✓ Hidden games detection"
            echo ""
          '';

          # For C library linking
          LD_LIBRARY_PATH = pkgs.lib.makeLibraryPath buildInputs;
          PKG_CONFIG_PATH = "${pkgs.libarchive}/lib/pkgconfig:${pkgs.leveldb}/lib/pkgconfig";
          
          # C compiler for Zig's C interop
          CC = "${pkgs.gcc}/bin/gcc";
        };

        # ═══════════════════════════════════════════════════════════════════════════
        # PACKAGES
        # ═══════════════════════════════════════════════════════════════════════════
        packages = {
          default = self.packages.${system}.stl-next;

          stl-next = pkgs.stdenv.mkDerivation {
            pname = "stl-next";
            version = "0.2.0"; # Phase 2

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

          # Minimal build without C dependencies
          stl-next-minimal = pkgs.stdenv.mkDerivation {
            pname = "stl-next-minimal";
            version = "0.2.0";

            src = self;

            nativeBuildInputs = [ zig ];

            buildPhase = ''
              export ZIG_GLOBAL_CACHE_DIR="$TMPDIR/zig-cache"
              zig build -Doptimize=ReleaseFast -Dno-leveldb=true --prefix $out
            '';

            installPhase = ":";

            meta = with pkgs.lib; {
              description = "STL-Next minimal (no LevelDB)";
              license = licenses.gpl3;
              platforms = platforms.linux;
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
