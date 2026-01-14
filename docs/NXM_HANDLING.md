# NXM Protocol Handling in STL-Next

This document explains how STL-Next handles NXM (Nexus Mods) protocol URLs, and specifically how it fixes the critical URL truncation bug present in the original SteamTinkerLaunch.

## The Bug That Started It All

### Original STL Behavior

The original SteamTinkerLaunch had a 6+ month unfixed bug where NXM collection URLs were being truncated when passed to Vortex through Wine.

**Root Cause**: Wine interprets forward slashes (`/`) as command-line switches when parsing arguments. This caused parts of the URL to be silently dropped.

**Example**:
```bash
# User clicks browser link:
nxm://stardewvalley/collections/tckf0m/revisions/100

# What STL passed to Wine/Vortex:
nxm://stardewvalley/collections/tckf0m
#                                      ^^^^^^^^^^^^^^^^^^^^
#                                      /revisions/100 LOST!

# Vortex error:
"Invalid URL: invalid nxm url"
```

### STL-Next Fix

STL-Next URL-encodes all path separators before passing to Wine:

```bash
# Input:
nxm://stardewvalley/collections/tckf0m/revisions/100

# Wine-safe encoding:
nxm://stardewvalley%2Fcollections%2Ftckf0m%2Frevisions%2F100

# Vortex correctly receives and decodes:
nxm://stardewvalley/collections/tckf0m/revisions/100
# /revisions/100 PRESERVED! ✅
```

## NXM URL Formats

STL-Next supports two NXM URL formats:

### 1. Mod Download URLs

```
nxm://{game}/mods/{mod_id}/files/{file_id}[?key={api_key}&expires={timestamp}]
```

**Components**:
- `game` - Nexus game domain (e.g., `stardewvalley`, `skyrimse`)
- `mod_id` - Numeric mod ID on Nexus
- `file_id` - Numeric file ID for specific download
- `key` (optional) - API key for premium download
- `expires` (optional) - Unix timestamp for link expiry

**Example**:
```
nxm://stardewvalley/mods/12345/files/67890?key=abc123&expires=1704067200
```

### 2. Collection URLs

```
nxm://{game}/collections/{slug}/revisions/{revision_id}[?key={api_key}]
```

**Components**:
- `game` - Nexus game domain
- `slug` - Collection slug (alphanumeric identifier)
- `revision_id` - Collection revision number (CRITICAL!)
- `key` (optional) - API key

**Example**:
```
nxm://stardewvalley/collections/tckf0m/revisions/100
```

⚠️ **The `revisions` segment is what the original STL was dropping!**

## Usage

### CLI

```bash
# Handle an NXM link
./stl-next nxm "nxm://stardewvalley/mods/12345/files/67890"

# Output:
NXM Handler: nxm://stardewvalley/mods/12345/files/67890
  Parsed: Mod: stardewvalley/mods/12345/files/67890
  Status: Valid link
  Wine-safe: nxm://stardewvalley%2Fmods%2F12345%2Ffiles%2F67890
```

```bash
# Collection URL
./stl-next nxm "nxm://stardewvalley/collections/tckf0m/revisions/100"

# Output:
NXM Handler: nxm://stardewvalley/collections/tckf0m/revisions/100
  Parsed: Collection: stardewvalley/collections/tckf0m/revisions/100
  Status: Valid link
  Wine-safe: nxm://stardewvalley%2Fcollections%2Ftckf0m%2Frevisions%2F100
```

### As Desktop Handler

To register STL-Next as the system NXM handler:

```bash
# Create desktop entry
cat > ~/.local/share/applications/stl-next-nxm.desktop << EOF
[Desktop Entry]
Type=Application
Name=STL-Next NXM Handler
Exec=/path/to/stl-next nxm %u
MimeType=x-scheme-handler/nxm;
NoDisplay=true
EOF

# Register as default handler
xdg-mime default stl-next-nxm.desktop x-scheme-handler/nxm

# Update database
update-desktop-database ~/.local/share/applications
```

## API Reference

### NxmLink Structure

```zig
pub const NxmLink = struct {
    link_type: NxmLinkType,      // .Mod, .Collection, or .Unknown
    game_domain: []const u8,     // e.g., "stardewvalley"
    
    // For mods
    mod_id: ?u32,                // e.g., 12345
    file_id: ?u32,               // e.g., 67890
    
    // For collections
    collection_slug: ?[]const u8, // e.g., "tckf0m"
    revision_id: ?u32,           // e.g., 100 (THE CRITICAL FIELD!)
    
    // Query params
    key: ?[]const u8,            // API key
    expires: ?u64,               // Expiry timestamp
    
    original_url: []const u8,    // Original unparsed URL
};
```

### NxmError Types

```zig
pub const NxmError = error{
    InvalidScheme,     // Not "nxm://"
    MissingGameDomain, // No game after scheme
    MissingModId,      // /mods/ without ID
    MissingFileId,     // /files/ without ID
    InvalidModId,      // Non-numeric mod ID
    InvalidFileId,     // Non-numeric file ID
    InvalidRevisionId, // Non-numeric revision
    MalformedUrl,      // General parse failure
    UrlTooLong,        // > 2048 characters
    EmptyUrl,          // Empty string
};
```

### Parsing Example

```zig
const modding = @import("modding/manager.zig");

// Parse a link
var link = try modding.NxmLink.parse(allocator, url);
defer link.deinit(allocator);

// Check validity
if (!link.isValid()) {
    std.log.err("Invalid NXM link", .{});
    return;
}

// Get display string
const display = try link.toDisplayString(allocator);
defer allocator.free(display);
std.log.info("Parsed: {s}", .{display});

// Get Wine-safe encoding
const encoded = try link.encodeForWine(allocator);
defer allocator.free(encoded);
```

## Validation

STL-Next performs strict validation on NXM URLs:

1. **Scheme Check**: Must start with `nxm://`
2. **Length Limit**: Max 2048 characters (DoS prevention)
3. **Game Domain**: Must be non-empty
4. **ID Validation**: Mod/file/revision IDs must be valid u32
5. **Type Detection**: Correctly identifies mods vs collections

### Edge Cases Handled

| Input | Result |
|-------|--------|
| `""` | `EmptyUrl` error |
| `http://...` | `InvalidScheme` error |
| `nxm://` | `MissingGameDomain` error |
| `nxm://game/mods/abc` | `InvalidModId` error |
| `nxm://game/mods/999999999999` | `InvalidModId` (overflow) |
| `nxm://game/collections/slug` | Valid, `revision_id = null` |

## Testing

The NXM parser has comprehensive tests in `src/tests/edge_cases.zig`:

```zig
test "nxm: collection url preserves revisions (THE ORIGINAL BUG)" {
    const url = "nxm://stardewvalley/collections/tckf0m/revisions/100";
    
    var link = try modding.NxmLink.parse(std.testing.allocator, url);
    defer link.deinit(std.testing.allocator);
    
    // CRITICAL: Revision ID must be preserved!
    try std.testing.expectEqual(@as(u32, 100), link.revision_id.?);
}

test "nxm: wine encoding escapes all slashes" {
    // ... verifies no raw slashes after encoding
}
```

Run tests with:
```bash
zig build test
```

## Integration with Mod Managers

### Vortex

When Vortex is detected, STL-Next will:
1. Parse the NXM URL
2. URL-encode for Wine safety
3. Forward to Vortex's NXM handler

```zig
if (ctx.config.manager == .Vortex) {
    const encoded = try link.encodeForWine(allocator);
    // Launch Vortex with encoded URL
}
```

### MO2 (Mod Organizer 2)

Similar handling for MO2's `nxmhandler.exe`:

```zig
if (ctx.config.manager == .MO2) {
    const encoded = try link.encodeForWine(allocator);
    // Launch MO2's handler with encoded URL
}
```

## Future Enhancements

### Phase 5 Plans

1. **Direct Download**: Download mods without external manager
2. **Collection Import**: Parse collection metadata
3. **Mod Conflict Detection**: Check for overwrites
4. **Installation Queue**: Batch process multiple links

### Potential Protocol Extensions

1. **NXM v2**: Support for new Nexus API features
2. **Premium Integration**: Direct API downloads
3. **Mod Update Checks**: Compare installed vs available

## Troubleshooting

### Common Issues

**"Invalid URL: invalid nxm url" in Vortex**
- This was the original bug. With STL-Next, URLs are properly encoded.
- If still occurring, check that STL-Next is actually handling the link.

**Collection shows wrong revision**
- Verify the full URL includes `/revisions/{number}`
- Check STL-Next logs for the parsed revision ID

**Link not being handled**
- Verify `xdg-mime query default x-scheme-handler/nxm` returns STL-Next
- Check browser settings for NXM protocol handler

### Debug Mode

Enable debug logging:
```bash
STL_LOG_LEVEL=debug ./stl-next nxm "nxm://..."
```

This will show:
- Original URL
- Parsed components
- Wine-safe encoding
- Mod manager detection

