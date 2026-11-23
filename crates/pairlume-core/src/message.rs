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

#[derive(Clone, Copy, Debug, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum CallState {
    /// someone calls this phone
    Ringing,
    /// this phone calls someone and it rings there
    Dialing,
    Talking,
    /// over; `missed` when nobody answered a call that came
    Ended,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum CallAction {
    Answer,
    /// says no to a ringing call, or ends the one there is
    End,
    /// calls `number`
    Dial,
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
    // ---- texts. The computer asks (`req` is its number for the question), the phone answers with the same number
    SmsList {
        req: u64,
        limit: u32,
        before: Option<i64>,
    },
    SmsThreads {
        req: u64,
        threads: Vec<Thread>,
        more: bool,
    },
    SmsRead {
        req: u64,
        thread: i64,
        limit: u32,
        before: Option<i64>,
    },
    SmsMessages {
        req: u64,
        thread: i64,
        messages: Vec<Text>,
        more: bool,
    },
    SmsSend {
        req: u64,
        to: String,
        text: String,
    },
    /// the phone took it over; whether it arrives is up to the network
    SmsSent {
        req: u64,
    },
    /// pictures from the contacts, for these numbers
    SmsPhotos {
        req: u64,
        addresses: Vec<String>,
    },
    SmsFaces {
        req: u64,
        faces: Vec<Face>,
    },
    /// a question that could not be answered
    SmsError {
        req: u64,
        reason: String,
    },
    /// a text has just come
    SmsNew {
        thread: Thread,
        message: Text,
    },
    // ---- calls
    /// what the phone's call is doing now
    Call {
        state: CallState,
        /// empty when the network hides it
        #[serde(default)]
        number: String,
        /// from the contacts
        #[serde(default)]
        name: String,
        #[serde(default, skip_serializing_if = "std::ops::Not::not")]
        missed: bool,
        /// the contact's picture while it rings (PNG, base64)
        #[serde(default, skip_serializing_if = "Option::is_none")]
        png: Option<String>,
    },
    CallDo {
        req: u64,
        what: CallAction,
        #[serde(default, skip_serializing_if = "Option::is_none")]
        number: Option<String>,
    },
    CallDone {
        req: u64,
    },
    CallError {
        req: u64,
        reason: String,
    },
    Ping,
    Pong,
    /// something from a newer version: ignored
    #[serde(other)]
    Unknown,
}

/// a conversation
#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
pub struct Thread {
    pub id: i64,
    /// the number, or a name a network sends texts under
    pub address: String,
    /// from the phone's contacts, empty when it is not in them
    #[serde(default)]
    pub name: String,
    #[serde(default)]
    pub snippet: String,
    /// milliseconds since 1970
    pub date: i64,
    #[serde(default)]
    pub unread: u32,
}

#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
pub struct Text {
    pub id: i64,
    /// sent by the phone's owner
    pub out: bool,
    pub text: String,
    pub date: i64,
    #[serde(default, skip_serializing_if = "std::ops::Not::not")]
    pub failed: bool,
}

/// a round picture (PNG, base64) of whoever has this number
#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
pub struct Face {
    pub address: String,
    pub png: String,
}

impl Face {
    /// base64 of something that starts like a PNG and is no larger than a small picture
    fn sound(&self) -> bool {
        let ok = |b: u8| b.is_ascii_alphanumeric() || matches!(b, b'+' | b'/' | b'=');
        self.address.len() <= 64 && self.png.len() <= 48 * 1024 && self.png.starts_with("iVBORw0KGgo") && self.png.bytes().all(ok)
    }
}

impl Text {
    fn clean(&mut self) {
        self.text = clean_text(&self.text);
    }
}
impl Thread {
    fn clean(&mut self) {
        self.address = crate::store::clean_name(&self.address);
        if !self.name.is_empty() {
            self.name = crate::store::clean_name(&self.name);
        }
        self.snippet = clean_text(&self.snippet).chars().take(200).collect();
    }
}

/// new lines and tabs stay, everything that could play with a window or a terminal goes
pub fn clean_text(s: &str) -> String {
    let bad =
        |c: char| (c.is_control() && c != '\n' && c != '\t') || matches!(c, '\u{202a}'..='\u{202e}' | '\u{2066}'..='\u{2069}');
    s.chars().filter(|c| !bad(*c)).take(8000).collect()
}

impl Msg {
    /// the number of the question this answers
    pub fn answers(&self) -> Option<u64> {
        match self {
            Self::SmsThreads { req, .. }
            | Self::SmsMessages { req, .. }
            | Self::SmsFaces { req, .. }
            | Self::SmsSent { req }
            | Self::SmsError { req, .. }
            | Self::CallDone { req }
            | Self::CallError { req, .. } => Some(*req),
            _ => None,
        }
    }

    /// what comes from a phone is other people's text
    pub fn clean(mut self) -> Self {
        match &mut self {
            Self::SmsThreads { threads, .. } => threads.iter_mut().for_each(Thread::clean),
            Self::SmsMessages { messages, .. } => messages.iter_mut().for_each(Text::clean),
            Self::SmsNew { thread, message } => {
                thread.clean();
                message.clean();
            }
            Self::SmsFaces { faces, .. } => faces.retain(Face::sound),
            Self::SmsError { reason, .. } | Self::CallError { reason, .. } => *reason = crate::store::clean_name(reason),
            Self::Call { number, name, png, .. } => {
                *number = crate::store::clean_name(number).chars().take(40).collect();
                *name = crate::store::clean_name(name);
                if png.as_ref().is_some_and(|p| !Face { address: String::new(), png: p.clone() }.sound()) {
                    *png = None;
                }
            }
            _ => {}
        }
        self
    }

    /// the permission a message from the phone needs (none: it is part of the link itself)
    pub fn needs(&self) -> Option<Capability> {
        match self {
            Self::Battery { .. } => Some(Capability::Battery),
            Self::SmsThreads { .. }
            | Self::SmsMessages { .. }
            | Self::SmsFaces { .. }
            | Self::SmsSent { .. }
            | Self::SmsError { .. }
            | Self::SmsNew { .. } => Some(Capability::Sms),
            Self::Call { .. } | Self::CallDone { .. } | Self::CallError { .. } => Some(Capability::Calls),
            _ => None,
        }
    }
}
