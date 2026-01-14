{
  description = "STL-Next: Steam Tinker Launch - Next Generation";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
    zig-overlay.url = "github:mitchellh/zig-overlay";
    zls.url = "github:zigtools/zls";
  };

  outputs = { self, nixpkgs, flake-utils, zig-overlay, zls }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = nixpkgs.legacyPackages.${system};
        zig = zig-overlay.packages.${system}."0.13.0";
      in
      {
        devShells.default = pkgs.mkShell {
          packages = with pkgs; [
            zig
            zls.packages.${system}.zls
            just
            hyperfine
          ];

          shellHook = ''
            echo "╔══════════════════════════════════════════╗"
            echo "║      STL-Next Development Shell          ║"
            echo "║           Phase 4: IPC + Wait Requester         ║"
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
            echo "Phase 4 Features:"
            echo "  ✓ Tinker module interface (plugin system)"
            echo "  ✓ MangoHud overlay support"
            echo "  ✓ Gamescope wrapper support"
            echo "  ✓ GameMode integration"
            echo "  ✓ Per-game JSON configuration"
            echo ""
          '';
        };

        packages.default = pkgs.stdenv.mkDerivation {
          pname = "stl-next";
          version = "0.3.0-alpha";
          src = self;
          nativeBuildInputs = [ zig ];
          
          buildPhase = ''
            zig build -Doptimize=ReleaseFast
          '';

          installPhase = ''
            mkdir -p $out/bin
            cp zig-out/bin/stl-next $out/bin/
          '';
        };
      });
}
