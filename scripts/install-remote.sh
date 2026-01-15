#!/usr/bin/env bash
# STL-Next Remote Installation Script
# Usage: ./install-remote.sh <user@hostname>

set -e

TARGET="${1:-evie@evie-desktop-1}"
STL_NEXT_DIR="$(cd "$(dirname "$0")/.." && pwd)"

echo "╔════════════════════════════════════════════════════════════════╗"
echo "║ STL-Next Remote Installation                                   ║"
echo "╠════════════════════════════════════════════════════════════════╣"
echo "║ Target: $TARGET"
echo "╚════════════════════════════════════════════════════════════════╝"
echo ""

# Check SSH connectivity
echo "→ Checking SSH connection..."
if ! ssh -o ConnectTimeout=5 "$TARGET" "echo 'SSH OK'"; then
    echo "❌ Cannot connect to $TARGET"
    echo "   Make sure the machine is online and SSH is enabled"
    exit 1
fi

# Check if Nix is available on target
echo "→ Checking for Nix on target..."
if ssh "$TARGET" "which nix" &>/dev/null; then
    echo "✅ Nix found - will use nix build"
    INSTALL_METHOD="nix"
else
    echo "⚠️ Nix not found - will copy binary"
    INSTALL_METHOD="binary"
fi

# Get target user's home directory
REMOTE_HOME=$(ssh "$TARGET" 'echo $HOME')
echo "→ Remote home: $REMOTE_HOME"

if [ "$INSTALL_METHOD" = "nix" ]; then
    echo ""
    echo "=== Building on remote via Nix ==="
    # Copy flake to remote and build
    ssh "$TARGET" "mkdir -p /tmp/stl-next-install"
    rsync -av --exclude='.git' --exclude='zig-out' --exclude='zig-cache' --exclude='.zig-cache' \
        "$STL_NEXT_DIR/" "$TARGET:/tmp/stl-next-install/"
    
    echo "→ Building STL-Next on remote..."
    ssh "$TARGET" "cd /tmp/stl-next-install && nix build .#default"
    
    # Install to user's path
    echo "→ Installing to ~/.local/bin..."
    ssh "$TARGET" "mkdir -p ~/.local/bin && cp -L /tmp/stl-next-install/result/bin/stl-next ~/.local/bin/"
    
    STL_BINARY="$REMOTE_HOME/.local/bin/stl-next"
else
    echo ""
    echo "=== Copying prebuilt binary ==="
    # Build locally and copy
    echo "→ Building locally..."
    cd "$STL_NEXT_DIR"
    nix build .#default
    
    echo "→ Copying binary to remote..."
    ssh "$TARGET" "mkdir -p ~/.local/bin"
    scp "$STL_NEXT_DIR/result/bin/stl-next" "$TARGET:~/.local/bin/"
    
    STL_BINARY="$REMOTE_HOME/.local/bin/stl-next"
fi

echo ""
echo "=== Setting up Steam Compatibility Tool ==="
COMPAT_DIR="$REMOTE_HOME/.local/share/Steam/compatibilitytools.d/STL-Next"

ssh "$TARGET" "mkdir -p $COMPAT_DIR"

# Create compatibilitytool.vdf
ssh "$TARGET" "cat > $COMPAT_DIR/compatibilitytool.vdf << 'VDFEOF'
\"compatibilitytools\"
{
  \"compat_tools\"
  {
    \"STL-Next\"
    {
      \"install_path\" \".\"
      \"display_name\" \"STL-Next v0.9.0\"
      \"from_oslist\" \"windows\"
      \"to_oslist\" \"linux\"
    }
  }
}
VDFEOF"

# Create toolmanifest.vdf
ssh "$TARGET" "cat > $COMPAT_DIR/toolmanifest.vdf << 'VDFEOF'
\"manifest\"
{
  \"version\" \"2\"
  \"commandline\" \"/proton %verb%\"
}
VDFEOF"

# Create proton launcher script (use heredoc properly)
ssh "$TARGET" bash -c "'cat > $COMPAT_DIR/proton'" << 'PROTONEOF'
#!/usr/bin/env bash
# STL-Next Steam compatibility wrapper
SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"
STL_NEXT="$SCRIPT_DIR/stl-next"
SteamAppId="${SteamAppId:-}"
echo "[STL-Next] Launching AppID: $SteamAppId" >&2
VERB="${1:-run}"
shift
exec "$STL_NEXT" run "$SteamAppId" "$@"
PROTONEOF
ssh "$TARGET" "chmod +x $COMPAT_DIR/proton"

# Symlink the binary
ssh "$TARGET" "ln -sf $STL_BINARY $COMPAT_DIR/stl-next"

echo ""
echo "=== Registering NXM Handler ==="
ssh "$TARGET" "mkdir -p ~/.local/share/applications"
ssh "$TARGET" "cat > ~/.local/share/applications/stl-next-nxm.desktop << 'DESKTOPEOF'
[Desktop Entry]
Type=Application
Name=STL-Next NXM Handler
Comment=Handle Nexus Mods NXM protocol links
Exec=$STL_BINARY nxm %u
MimeType=x-scheme-handler/nxm;
NoDisplay=true
Categories=Game;
DESKTOPEOF"

echo ""
echo "=== Verifying Installation ==="
echo "→ Testing STL-Next..."
ssh "$TARGET" "$STL_BINARY version" || echo "⚠️ Could not verify installation"

echo ""
echo "╔════════════════════════════════════════════════════════════════╗"
echo "║ ✅ Installation Complete!                                       ║"
echo "╠════════════════════════════════════════════════════════════════╣"
echo "║ Next steps:                                                    ║"
echo "║   1. Restart Steam on $TARGET                                  ║"
echo "║   2. Right-click a game → Properties → Compatibility          ║"
echo "║   3. Select 'STL-Next v0.9.0' as compatibility tool            ║"
echo "╚════════════════════════════════════════════════════════════════╝"

