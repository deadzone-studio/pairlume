// SPDX-License-Identifier: GPL-3.0-or-later
//! Everything the two ends say to each other (docs/protocol.md).
use serde::{Deserialize, Serialize};
use std::{collections::BTreeSet, fmt, str::FromStr};

#[derive(Clone, Copy, Debug, PartialEq, Eq, PartialOrd, Ord, Hash, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum Capability {
    Battery,
    Sms,
    Calls,
    Notifications,
    Files,
    Clipboard,
    Screen,
    Camera,
}

impl Capability {
    pub const ALL: [Capability; 8] =
        [Self::Battery, Self::Sms, Self::Calls, Self::Notifications, Self::Files, Self::Clipboard, Self::Screen, Self::Camera];
}

impl fmt::Display for Capability {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.write_str(match self {
            Self::Battery => "battery",
            Self::Sms => "sms",
            Self::Calls => "calls",
            Self::Notifications => "notifications",
            Self::Files => "files",
            Self::Clipboard => "clipboard",
            Self::Screen => "screen",
            Self::Camera => "camera",
        })
    }
}

impl FromStr for Capability {
    type Err = anyhow::Error;
    fn from_str(s: &str) -> Result<Self, Self::Err> {
        (Self::ALL.into_iter().find(|c| c.to_string() == s)).ok_or_else(|| anyhow::anyhow!("no such permission: {s}"))
    }
}

#[derive(Clone, Copy, Debug, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum PairMode {
    /// shaking the phone: both screens show a code and both sides say yes
    Shake,
    /// the phone scanned the code on the computer's screen
    Qr,
    /// the phone's user typed the six digits from the computer's screen
    Digits,
}

#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
#[serde(tag = "t", rename_all = "snake_case")]
pub enum Msg {
    Hello {
        v: u32,
        name: String,
    },
    PairStart {
        mode: PairMode,
    },
    Commit {
        mac: String,
    },
    Nonce {
        nonce: String,
    },
    Proof {
        mac: String,
    },
    Confirm {
        ok: bool,
    },
    Fail {
        reason: String,
    },
    /// the computer: what this phone may do right now
    Allowed {
        caps: BTreeSet<Capability>,
    },
    /// the computer: that message needs a permission it does not have
    Denied {
        cap: Capability,
    },
    Battery {
        percent: u8,
        charging: bool,
    },
    Ping,
    Pong,
    /// something from a newer version: ignored
    #[serde(other)]
    Unknown,
}

impl Msg {
    /// the permission a message from the phone needs (none: it is part of the link itself)
    pub fn needs(&self) -> Option<Capability> {
        match self {
            Self::Battery { .. } => Some(Capability::Battery),
            _ => None,
        }
    }
}
