// SPDX-License-Identifier: GPL-3.0-or-later
//! The part of Pairlume both ends share: who a device is, the encrypted link, pairing, and the messages.
pub mod client;
pub mod identity;
pub mod message;
pub mod pairing;
pub mod store;
pub mod tls;
pub mod wire;

pub const PROTOCOL_VERSION: u32 = 1;
pub const DEFAULT_PORT: u16 = 47321;
pub const ALPN: &[u8] = b"pairlume/1";
