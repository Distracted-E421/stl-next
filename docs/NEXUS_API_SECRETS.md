# Nexus Mods API Integration

STL-Next integrates with the official Nexus Mods API to provide premium features like direct mod downloads, tracking, and endorsements.

## Getting Your API Key

1. Visit [https://www.nexusmods.com/users/myaccount?tab=api%20access](https://www.nexusmods.com/users/myaccount?tab=api%20access)
2. Generate a Personal API Key
3. **Never share this key with anyone**

## API Key Configuration

STL-Next looks for your API key in the following locations (in order):

### 1. Environment Variable (Recommended for Testing)

```bash
export STL_NEXUS_API_KEY="your_api_key_here"
./stl-next ...
```

### 2. Config File (Regular Linux Users)

```bash
mkdir -p ~/.config/stl-next
echo "your_api_key_here" > ~/.config/stl-next/nexus_api_key
chmod 600 ~/.config/stl-next/nexus_api_key
```

### 3. NixOS with sops-nix (Recommended for NixOS)

```nix
# In your flake.nix inputs:
inputs.sops-nix.url = "github:Mic92/sops-nix";

# In your configuration.nix:
{ config, ... }:
{
  imports = [ inputs.sops-nix.nixosModules.sops ];

  sops.defaultSopsFile = ./secrets/secrets.yaml;
  sops.defaultSopsFormat = "yaml";

  sops.secrets.nexus_api_key = {
    owner = config.users.users.YOUR_USERNAME.name;
    group = "users";
    mode = "0400";
  };

  # Make available to STL-Next
  environment.sessionVariables = {
    STL_NEXUS_API_KEY_FILE = config.sops.secrets.nexus_api_key.path;
  };
}
```

Create `secrets/secrets.yaml`:
```yaml
nexus_api_key: ENC[AES256_GCM,data:...,tag:...,type:str]
```

Encrypt with sops:
```bash
sops secrets/secrets.yaml
# Add: nexus_api_key: your_actual_api_key
```

### 4. NixOS with agenix

```nix
# In your configuration.nix:
{ config, ... }:
{
  age.secrets.nexus_api_key = {
    file = ./secrets/nexus_api_key.age;
    owner = "YOUR_USERNAME";
    mode = "400";
  };
}
```

Create encrypted secret:
```bash
age -r "$(cat ~/.ssh/id_ed25519.pub)" -o secrets/nexus_api_key.age <<< "your_api_key"
```

### 5. Home Manager Integration

```nix
# In your home.nix:
{ config, pkgs, ... }:
{
  # Store encrypted in your repo, decrypt at activation
  home.file.".config/stl-next/nexus_api_key" = {
    source = config.sops.secrets.nexus_api_key.path;
    # Or use a direct file with restrictive permissions:
    # text = builtins.readFile ./secrets/nexus_api_key;
  };
}
```

## Rate Limits

The Nexus Mods API has rate limits:

| Limit | Amount | Reset |
|-------|--------|-------|
| Daily | 2,500 requests | Midnight UTC |
| Hourly (after daily exceeded) | 100 requests | Every hour |
| Per-second | 30 requests | Burst allowed |

STL-Next tracks these limits via response headers:
- `X-RL-Daily-Remaining`
- `X-RL-Hourly-Remaining`

## Premium vs Free Users

| Feature | Free | Premium |
|---------|------|---------|
| Mod info | ✅ | ✅ |
| File info | ✅ | ✅ |
| Track mods | ✅ | ✅ |
| Endorse mods | ✅ | ✅ |
| Direct download links | ❌ | ✅ |
| NXM protocol download | ✅ | ✅ |

**Free users** can still download via NXM links (click download on website, STL-Next catches the link).

**Premium users** get direct download links via API, enabling:
- Background downloads
- Batch downloads
- Collection installation
- No browser needed

## API Endpoints Used

```
GET /v1/users/validate.json          - Validate API key
GET /v1/games/{game}/mods/{id}.json  - Get mod info
GET /v1/games/{game}/mods/{id}/files.json - List mod files
GET /v1/games/{game}/mods/{id}/files/{file_id}/download_link.json - Download link (Premium)
POST /v1/games/{game}/mods/{id}/endorse.json - Endorse mod
GET /v1/user/tracked_mods.json       - Get tracked mods
POST /v1/user/tracked_mods.json      - Track a mod
```

## Security Best Practices

1. **Never commit API keys to git** - Use `.gitignore`:
   ```
   nexus_api_key
   *.age
   secrets.yaml
   ```

2. **Use restricted file permissions**:
   ```bash
   chmod 600 ~/.config/stl-next/nexus_api_key
   ```

3. **NixOS users**: Use sops-nix or agenix for declarative secret management

4. **Rotate keys periodically** at the Nexus Mods API page

5. **Monitor rate limits** to avoid hitting limits during batch operations

