//! IPC Module - Daemon/Client communication for STL-Next
//!
//! Uses Unix Domain Sockets with JSON protocol

pub const protocol = @import("protocol.zig");
pub const server = @import("server.zig");
pub const client = @import("client.zig");

pub const Server = server.Server;
pub const Client = client.Client;
pub const Action = protocol.Action;
pub const DaemonState = protocol.DaemonState;
pub const ClientMessage = protocol.ClientMessage;
pub const DaemonMessage = protocol.DaemonMessage;

test {
    _ = protocol;
    _ = server;
    _ = client;
}

