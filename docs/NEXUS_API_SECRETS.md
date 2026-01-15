# Nexus Mods API Key Management

STL-Next integrates with the official Nexus Mods API v1 to provide premium features like direct mod downloads, update tracking, and endorsements.

## Getting Your API Key

1. Visit [https://www.nexusmods.com/users/myaccount?tab=api%20access](https://www.nexusmods.com/users/myaccount?tab=api%20access)
2. Click "Generate API Key" (or "Request API Key" if first time)
3. Copy the key - **it will only be shown once!**
4. **Never share this key with anyone**

## API Key Configuration Methods

STL-Next searches for your API key in this order:

### 1. Environment Variable (Recommended for Testing)

```bash
export STL_NEXUS_API_KEY="your_api_key_here"
stl-next nexus-whoami
```

### 2. Config File (Regular Linux Users)

```bash
mkdir -p ~/.config/stl-next
echo "your_api_key_here" > ~/.config/stl-next/nexus_api_key
chmod 600 ~/.config/stl-next/nexus_api_key
```

### 3. Interactive Login

```bash
stl-next nexus-login YOUR_API_KEY
# Or without argument for interactive prompt:
stl-next nexus-login
```

### 4. NixOS with sops-nix (Recommended for NixOS)

[sops-nix](https://github.com/Mic92/sops-nix) provides encrypted secret management.

**Step 1: Add sops-nix to your flake:**

```nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    sops-nix.url = "github:Mic92/sops-nix";
    stl-next.url = "github:your-username/stl-next";
  };
}
```

**Step 2: Create encrypted secret:**

```bash
# Initialize sops if you haven't
sops --config .sops.yaml secrets/nexus.yaml
```

**secrets/nexus.yaml** (encrypted):
```yaml
nexus_api_key: ENC[AES256_GCM,data:...,type:str]
```

**Step 3: Configure NixOS module:**

```nix
{ config, pkgs, inputs, ... }:
{
  imports = [
    inputs.sops-nix.nixosModules.default
    inputs.stl-next.nixosModules.default
  ];

  sops.secrets.nexus_api_key = {
    sopsFile = ./secrets/nexus.yaml;
    owner = "youruser";
    group = "users";
    mode = "0400";
  };

  # STL-Next will auto-discover from /run/secrets/nexus_api_key
  programs.stl-next = {
    enable = true;
    registerNxmHandler = true;
  };
}
```

### 5. NixOS with agenix (Alternative)

[agenix](https://github.com/ryantm/agenix) uses age encryption for secrets.

**Step 1: Add agenix to your flake:**

```nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    agenix.url = "github:ryantm/agenix";
    stl-next.url = "github:your-username/stl-next";
  };
}
```

**Step 2: Create encrypted secret:**

```bash
# Create age key if needed
age-keygen -o ~/.config/sops/age/keys.txt

# Encrypt the API key
echo "your_api_key" | age -r age1... > secrets/nexus_api_key.age
```

**Step 3: Configure NixOS:**

```nix
{ config, pkgs, inputs, ... }:
{
  imports = [
    inputs.agenix.nixosModules.default
    inputs.stl-next.nixosModules.default
  ];

  age.secrets.nexus_api_key = {
    file = ./secrets/nexus_api_key.age;
    owner = "youruser";
    group = "users";
    mode = "0400";
  };

  # STL-Next will auto-discover from /run/agenix/nexus_api_key
  programs.stl-next = {
    enable = true;
    registerNxmHandler = true;
  };
}
```

### 6. Home Manager Integration

For user-level secret management:

```nix
{ config, pkgs, inputs, ... }:
{
  imports = [
    inputs.stl-next.homeManagerModules.default
  ];

  programs.stl-next = {
    enable = true;
    registerNxmHandler = true;
    # Key will be read from ~/.config/stl-next/nexus_api_key
  };

  # Create the config directory
  xdg.configFile."stl-next/.keep".text = "";
}
```

Then manually add your key:

```bash
echo "your_api_key" > ~/.config/stl-next/nexus_api_key
chmod 600 ~/.config/stl-next/nexus_api_key
```

## API Key Discovery Order

STL-Next checks these locations in order:

1. `STL_NEXUS_API_KEY` environment variable
2. `~/.config/stl-next/nexus_api_key` file
3. `/run/secrets/nexus_api_key` (sops-nix)
4. `/run/agenix/nexus_api_key` (agenix)

The first valid key found is used.

## Verifying Your Key

```bash
stl-next nexus-whoami
```

Expected output:

```
Nexus Mods User Info
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  Username:    YourUsername
  User ID:     12345678
  Email:       your@email.com
  Premium:     ✓ Yes (direct downloads enabled)
  Supporter:   ✗ No
  Profile:     https://www.nexusmods.com/users/12345678
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

## Security Best Practices

### DO ✅

- Use file permissions `chmod 600` on key files
- Use encrypted secret managers (sops-nix, agenix) on NixOS
- Regenerate keys if compromised
- Keep keys out of version control

### DON'T ❌

- Hardcode API keys in source code
- Commit keys to git repositories
- Share keys with others
- Use keys in shell history (use `-login` instead of inline)

### Git Protection

STL-Next's `.gitignore` already includes:

```gitignore
# Nexus Mods API key - NEVER commit
nexus_api_key
*.env
.env*
```

## Rate Limits

The Nexus Mods API has these limits:

| Limit Type | Amount |
|------------|--------|
| Daily requests | 2,500 |
| Hourly (after daily) | 100 |
| Concurrent connections | 5 |

STL-Next handles rate limiting gracefully and will inform you when limits are reached.

## Premium Features

Premium Nexus Mods members get:

| Feature | Free | Premium |
|---------|------|---------|
| Mod info lookup | ✅ | ✅ |
| File listing | ✅ | ✅ |
| Update tracking | ✅ | ✅ |
| Endorsements | ✅ | ✅ |
| **Direct download links** | ❌ | ✅ |
| **Fast CDN downloads** | ❌ | ✅ |

Free users can still use the "Mod Manager Download" button on nexusmods.com, and STL-Next will catch the NXM link automatically.

## Troubleshooting

### "No API key found"

```bash
# Check if key file exists
ls -la ~/.config/stl-next/nexus_api_key

# Check environment variable
echo $STL_NEXUS_API_KEY

# Try interactive login
stl-next nexus-login
```

### "Invalid API key"

- Keys expire after 1 year of inactivity
- Regenerate at nexusmods.com/users/myaccount?tab=api%20access
- Ensure no extra whitespace in key file

### "Rate limited"

- Wait for the rate limit to reset (hourly for 100 requests)
- Premium accounts have higher limits
- Consider batching requests

### "Not Premium" for downloads

Free users cannot get direct download links. Options:

1. Upgrade to Nexus Premium
2. Use "Mod Manager Download" button on website
3. STL-Next will handle the NXM link from browser

## CLI Quick Reference

```bash
# Setup
stl-next nexus-login YOUR_API_KEY   # Save key
stl-next nexus-whoami               # Verify key

# Mod information
stl-next nexus-mod stardewvalley 21297        # Mod details
stl-next nexus-files stardewvalley 21297      # List files

# Downloads (Premium only)
stl-next nexus-download stardewvalley 21297 12345

# Tracking
stl-next nexus-track stardewvalley 21297      # Track mod
stl-next nexus-tracked                         # List tracked

# Common game domains
# stardewvalley, skyrimspecialedition, fallout4
# cyberpunk2077, baldursgate3, eldenring
```

## Related Documentation

- [NIXOS_INSTALLATION.md](NIXOS_INSTALLATION.md) - Full NixOS setup guide
- [FEATURE_ROADMAP.md](FEATURE_ROADMAP.md) - Project roadmap
- [README.md](../README.md) - Main documentation
