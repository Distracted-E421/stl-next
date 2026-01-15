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
        # Using Zig 0.15.2 from nixpkgs (zig-overlay doesn't have 0.15.x yet)
        zig = pkgs.zig;
        zlsPkg = zls.packages.${system}.zls;
      in
      {
        # Development shell
        devShells.default = pkgs.mkShell {
          packages = with pkgs; [
            zig
            zlsPkg
            just
            hyperfine
          ];

          shellHook = ''
            echo "╔══════════════════════════════════════════╗"
            echo "║      STL-Next Development Shell          ║"
            echo "║      Zig 0.15.x | Phase 5: GUI           ║"
            echo "╠══════════════════════════════════════════╣"
            echo "║ zig version: $(zig version)              ║"
            echo "╚══════════════════════════════════════════╝"
            echo ""
            echo "Commands:"
            echo "  zig build         Build debug binary"
            echo "  zig build run     Build and run"
            echo "  zig build test    Run unit tests"
            echo "  zig build -Doptimize=ReleaseFast  Build optimized release"
            echo ""
          '';
        };

        # Main package
        packages.default = pkgs.stdenv.mkDerivation {
          pname = "stl-next";
          version = "0.5.2-alpha";
          src = self;
          
          nativeBuildInputs = [ zig ];
          
          dontConfigure = true;
          dontInstall = true;
          
          buildPhase = ''
            export HOME=$TMPDIR
            export XDG_CACHE_HOME=$TMPDIR/.cache
            mkdir -p $out/bin
            # Build with glibc target to ensure compatibility on NixOS
            zig build -Doptimize=ReleaseFast -Dtarget=x86_64-linux-gnu --prefix $out
          '';
          
          meta = with pkgs.lib; {
            description = "Steam Tinker Launch - Next Generation";
            longDescription = ''
              A high-performance Steam game wrapper written in Zig.
              Features NXM protocol handling, Tinker modules (MangoHud, Gamescope, GameMode),
              non-Steam game management, and SteamGridDB integration.
            '';
            homepage = "https://github.com/e421/stl-next";
            license = licenses.gpl3;
            platforms = platforms.linux;
            mainProgram = "stl-next";
          };
        };
        
        # Convenience alias
        packages.stl-next = self.packages.${system}.default;
      })
    //
    {
      # NixOS module for system-wide installation
      nixosModules.default = { config, lib, pkgs, ... }: 
        let
          cfg = config.programs.stl-next;
          stlPackage = self.packages.${pkgs.system}.default;
        in {
          options.programs.stl-next = {
            enable = lib.mkEnableOption "STL-Next Steam game launcher";
            
            package = lib.mkOption {
              type = lib.types.package;
              default = stlPackage;
              defaultText = lib.literalExpression "stl-next.packages.\${pkgs.system}.default";
              description = "The STL-Next package to use";
            };
            
            registerNxmHandler = lib.mkOption {
              type = lib.types.bool;
              default = true;
              description = "Register STL-Next as the NXM protocol handler";
            };
          };
          
          config = lib.mkIf cfg.enable {
            environment.systemPackages = [ cfg.package ];
            
            # Register NXM protocol handler system-wide
            environment.etc = lib.mkIf cfg.registerNxmHandler {
              "xdg/applications/stl-next-nxm.desktop".text = ''
                [Desktop Entry]
                Type=Application
                Name=STL-Next NXM Handler
                Comment=Handle Nexus Mods NXM protocol links
                Exec=${cfg.package}/bin/stl-next nxm %u
                MimeType=x-scheme-handler/nxm;
                NoDisplay=true
                Categories=Game;
              '';
            };
          };
        };
      
      # Home Manager module
      homeManagerModules.default = { config, lib, pkgs, ... }:
        let
          cfg = config.programs.stl-next;
          stlPackage = self.packages.${pkgs.system}.default;
        in {
          options.programs.stl-next = {
            enable = lib.mkEnableOption "STL-Next Steam game launcher";
            
            package = lib.mkOption {
              type = lib.types.package;
              default = stlPackage;
              defaultText = lib.literalExpression "stl-next.packages.\${pkgs.system}.default";
              description = "The STL-Next package to use";
            };
            
            registerNxmHandler = lib.mkOption {
              type = lib.types.bool;
              default = true;
              description = "Register STL-Next as the NXM protocol handler";
            };
            
            defaultTinkers = lib.mkOption {
              type = lib.types.attrsOf lib.types.bool;
              default = {
                mangohud = false;
                gamescope = false;
                gamemode = false;
              };
              description = "Default tinker settings for new games";
            };
            
            countdownSeconds = lib.mkOption {
              type = lib.types.int;
              default = 10;
              description = "Default countdown seconds before launch";
            };
          };
          
          config = lib.mkIf cfg.enable {
            home.packages = [ cfg.package ];
            
            # Create default config
            xdg.configFile."stl-next/global.json".text = builtins.toJSON {
              default_tinkers = cfg.defaultTinkers;
              countdown_seconds = cfg.countdownSeconds;
            };
            
            # Register NXM handler for user
            xdg.desktopEntries = lib.mkIf cfg.registerNxmHandler {
              stl-next-nxm = {
                name = "STL-Next NXM Handler";
                comment = "Handle Nexus Mods NXM protocol links";
                exec = "${cfg.package}/bin/stl-next nxm %u";
                mimeType = [ "x-scheme-handler/nxm" ];
                noDisplay = true;
                categories = [ "Game" ];
              };
            };
            
            xdg.mimeApps.defaultApplications = lib.mkIf cfg.registerNxmHandler {
              "x-scheme-handler/nxm" = "stl-next-nxm.desktop";
            };
          };
        };
        
      # Aliases for easier access
      nixosModules.stl-next = self.nixosModules.default;
      homeManagerModules.stl-next = self.homeManagerModules.default;
    };
}
