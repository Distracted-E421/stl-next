//! UI Module - Wait Requester and User Interfaces
//!
//! Provides:
//! - TUI (Terminal UI) for SSH/headless
//! - Daemon for IPC-based wait requester
//! - (Future) Raylib GUI

pub const tui = @import("tui.zig");
pub const daemon = @import("daemon.zig");

pub const TUI = tui.TUI;
pub const WaitRequester = daemon.WaitRequester;
pub const runTUI = tui.runTUI;
pub const shouldShowWait = daemon.shouldShowWait;

test {
    _ = tui;
    _ = daemon;
}

