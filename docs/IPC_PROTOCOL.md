# STL-Next IPC Protocol Specification

**Version**: 1.0  
**Status**: Stable  
**Phase**: 4

## Overview

STL-Next uses a JSON-over-Unix-Domain-Sockets protocol for communication between the Wait Requester daemon and GUI/TUI clients. This allows real-time control of game launch parameters, tinker toggles, and countdown management.

## Transport Layer

### Socket Location

```
$XDG_RUNTIME_DIR/stl-next-{AppID}.sock
```

Example: `/run/user/1000/stl-next-413150.sock`

### Connection Parameters

| Parameter | Value |
|-----------|-------|
| Socket Type | `AF_UNIX`, `SOCK_STREAM` |
| Max Message Size | 64KB |
| Connection Timeout | 5000ms (default) |
| Max Retries | 3 |

## Message Format

All messages are JSON objects terminated by socket close. No explicit framing is used.

### Client → Daemon Messages

```json
{
  "action": "<ACTION_TYPE>",
  "tinker_id": "<optional_string>",
  "enabled": <optional_boolean>
}
```

#### Actions

| Action | Description | Parameters |
|--------|-------------|------------|
| `PAUSE_LAUNCH` | Pause the countdown, keeping daemon waiting | None |
| `RESUME_LAUNCH` | Resume a paused countdown | None |
| `PROCEED` | Skip countdown and launch immediately | None |
| `ABORT` | Cancel the launch entirely | None |
| `GET_STATUS` | Request current daemon state | None |
| `GET_GAME_INFO` | Request game information | None |
| `GET_TINKERS` | Get list of available tinkers | None |
| `TOGGLE_TINKER` | Toggle a specific tinker on/off | `tinker_id` |
| `UPDATE_CONFIG` | Update configuration (future) | TBD |

#### Example Messages

```json
// Pause the countdown
{"action": "PAUSE_LAUNCH"}

// Toggle MangoHud
{"action": "TOGGLE_TINKER", "tinker_id": "mangohud"}

// Launch immediately
{"action": "PROCEED"}
```

### Daemon → Client Messages

```json
{
  "state": "<DAEMON_STATE>",
  "countdown_seconds": <u8>,
  "game_name": "<string>",
  "app_id": <u32>,
  "mangohud_enabled": <boolean>,
  "gamescope_enabled": <boolean>,
  "gamemode_enabled": <boolean>,
  "error_msg": "<optional_string>"
}
```

#### Daemon States

| State | Description |
|-------|-------------|
| `INITIALIZING` | Daemon is starting up |
| `WAITING` | Countdown paused, waiting for client action |
| `COUNTDOWN` | Actively counting down to launch |
| `LAUNCHING` | Countdown complete, launching game |
| `RUNNING` | Game is running |
| `FINISHED` | Daemon is shutting down |
| `ERROR` | An error occurred |

#### Example Response

```json
{
  "state": "COUNTDOWN",
  "countdown_seconds": 7,
  "game_name": "Stardew Valley",
  "app_id": 413150,
  "mangohud_enabled": true,
  "gamescope_enabled": false,
  "gamemode_enabled": true
}
```

## Sequence Diagrams

### Normal Launch Flow

```
Client                          Daemon
  |                                |
  |-------- Connect -------------->|
  |<------- Status (COUNTDOWN) ----|
  |                                |
  |   ... countdown ticks ...      |
  |                                |
  |<------- Status (LAUNCHING) ----|
  |<------- Close Connection ------|
  |                                |
```

### Pause/Resume Flow

```
Client                          Daemon
  |                                |
  |-------- Connect -------------->|
  |<------- Status (COUNTDOWN) ----|
  |                                |
  |------ PAUSE_LAUNCH ----------->|
  |<------- Status (WAITING) ------|
  |                                |
  |   ... user configures tinkers...|
  |                                |
  |------ TOGGLE_TINKER ---------->|
  |<------- Status (WAITING) ------|
  |                                |
  |------ RESUME_LAUNCH ---------->|
  |<------- Status (COUNTDOWN) ----|
  |                                |
```

### Abort Flow

```
Client                          Daemon
  |                                |
  |-------- Connect -------------->|
  |<------- Status (COUNTDOWN) ----|
  |                                |
  |-------- ABORT ---------------->|
  |<------- Status (FINISHED) -----|
  |<------- Close Connection ------|
  |                                |
```

## Error Handling

### Client Errors

| Error | Description | Recovery |
|-------|-------------|----------|
| `DaemonNotRunning` | Socket file doesn't exist | Start daemon first |
| `ConnectionTimeout` | Connection took > timeout | Retry or check daemon |
| `ConnectionRefused` | Socket exists but daemon not accepting | Restart daemon |
| `EmptyResponse` | Daemon closed without response | Reconnect |
| `InvalidResponse` | Response wasn't valid JSON | Ignore and retry |
| `ResponseTooLarge` | Response > 64KB | Treat as error |

### Daemon Errors

The daemon will set `state` to `ERROR` and populate `error_msg`:

```json
{
  "state": "ERROR",
  "error_msg": "Failed to load game info",
  ...
}
```

## Tinker IDs

| ID | Tinker | Description |
|----|--------|-------------|
| `mangohud` | MangoHud | Performance overlay |
| `gamescope` | Gamescope | Compositor wrapper |
| `gamemode` | GameMode | System optimization |

Additional tinkers will be added in future phases:
- `reshade` - ReShade post-processing
- `vkbasalt` - vkBasalt filters
- `obs` - OBS capture

## Implementation Notes

### JSON Serialization

The protocol uses simple string concatenation for serialization rather than `std.json.stringify()` for performance reasons. Special characters in game names (quotes, backslashes) are escaped:

```zig
// Escape quotes and backslashes in game names
for (self.game_name) |c| {
    if (c == '"') {
        try buf.appendSlice("\\\"");
    } else if (c == '\\') {
        try buf.appendSlice("\\\\");
    } else {
        try buf.append(c);
    }
}
```

### JSON Parsing

Parsing uses substring search for robustness against minor format variations:

```zig
// Parse state - search for string match
if (std.mem.indexOf(u8, data, "COUNTDOWN") != null) return .COUNTDOWN;
```

### Socket Lifecycle

1. **Daemon**: Creates socket on `start()`, removes on `deinit()`
2. **Client**: Connects on-demand, reconnects if needed
3. **Cleanup**: Socket file is deleted when daemon stops

### Non-Blocking I/O

The server uses `poll()` for non-blocking accepts, allowing the daemon to:
- Process client messages
- Update countdown timer
- Check for external signals

```zig
var pfd = [_]std.posix.pollfd{.{
    .fd = socket,
    .events = std.posix.POLL.IN,
    .revents = 0,
}};
const poll_result = try std.posix.poll(&pfd, 0);  // Non-blocking
```

## Security Considerations

1. **Socket Permissions**: Socket created with default permissions (0600)
2. **Path Validation**: Socket path length checked against Unix max (108 bytes)
3. **Message Size**: Hard limit of 64KB prevents DoS
4. **No Authentication**: Assumes trusted local environment (same user)

## Future Extensions

### Planned for Phase 5

- **Multiple Clients**: Allow multiple TUI/GUI clients to connect
- **Event Streaming**: Push state changes to all connected clients
- **Config Updates**: Full configuration modification via IPC
- **Game Process Monitoring**: Real-time game PID and status

### Potential Protocol v2

- **Message Framing**: Length-prefixed messages for streaming
- **Binary Protocol**: MessagePack or similar for performance
- **Subscriptions**: Subscribe to specific state changes

## Testing

The protocol is tested in `src/tests/edge_cases.zig`:

```zig
test "ipc: action round-trip" {
    for (actions) |action| {
        const str = action.toString();
        const parsed = protocol.Action.fromString(str);
        try std.testing.expectEqual(action, parsed.?);
    }
}

test "ipc: daemon message with special characters" {
    // Tests game names with quotes, backslashes, etc.
}
```

## Reference Implementation

- **Protocol**: `src/ipc/protocol.zig`
- **Server**: `src/ipc/server.zig`
- **Client**: `src/ipc/client.zig`
- **Daemon**: `src/ui/daemon.zig`
- **TUI**: `src/ui/tui.zig`

