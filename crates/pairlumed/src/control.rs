// SPDX-License-Identifier: GPL-3.0-or-later
//! The local socket for windows and the command line: one JSON per line. Only the same user may connect.
use crate::{Daemon, DeviceStatus, Event, PAIRING_TIME};
use anyhow::{Context, Result, bail};
use pairlume_core::message::{CallAction, Capability, Msg};
use serde::{Deserialize, Serialize};
use std::{
    os::unix::fs::{MetadataExt, PermissionsExt},
    path::Path,
    sync::Arc,
};
use tokio::{
    io::{AsyncBufReadExt, AsyncReadExt, AsyncWriteExt, BufReader},
    net::{UnixListener, UnixStream},
    sync::broadcast::error::RecvError,
};

#[derive(Debug, Serialize, Deserialize)]
#[serde(tag = "cmd", rename_all = "snake_case")]
pub enum Request {
    Status,
    Pair,
    CancelPairing,
    Answer {
        yes: bool,
    },
    Allow {
        device: String,
        cap: Capability,
        on: bool,
    },
    Unpair {
        device: String,
    },
    SmsThreads {
        device: String,
        before: Option<i64>,
    },
    SmsMessages {
        device: String,
        thread: i64,
        before: Option<i64>,
    },
    SmsPhotos {
        device: String,
        addresses: Vec<String>,
    },
    SmsSend {
        device: String,
        to: String,
        text: String,
    },
    /// answer, end, or call a number
    Call {
        device: String,
        what: CallAction,
        #[serde(default)]
        number: Option<String>,
    },
    /// events from now on, until the connection is closed
    Watch,
}

#[derive(Debug, Default, Serialize, Deserialize)]
pub struct Reply {
    pub ok: bool,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub error: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub devices: Option<Vec<DeviceStatus>>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub pairing: Option<Event>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub answer: Option<Msg>,
}

const MAX_LINE: u64 = 64 * 1024;

pub fn listen(path: &Path) -> Result<UnixListener> {
    if std::os::unix::net::UnixStream::connect(path).is_ok() {
        bail!("pairlumed is already running ({})", path.display());
    }
    match std::fs::symlink_metadata(path) {
        Ok(m) if std::os::unix::fs::FileTypeExt::is_socket(&m.file_type()) => std::fs::remove_file(path)?,
        Ok(_) => bail!("{} is in the way", path.display()),
        Err(_) => {}
    }
    let l = UnixListener::bind(path).with_context(|| format!("cannot listen on {}", path.display()))?;
    std::fs::set_permissions(path, std::fs::Permissions::from_mode(0o600))?;
    Ok(l)
}

pub async fn serve(d: Arc<Daemon>, l: UnixListener) -> Result<()> {
    let me = std::fs::metadata("/proc/self")?.uid();
    loop {
        let (s, _) = l.accept().await?;
        if !s.peer_cred().is_ok_and(|c| c.uid() == me) {
            continue;
        }
        let d = d.clone();
        tokio::spawn(async move {
            let _ = client(d, s).await;
        });
    }
}

async fn client(d: Arc<Daemon>, s: UnixStream) -> Result<()> {
    let (r, mut w) = s.into_split();
    let mut r = BufReader::new(r);
    loop {
        let mut line = String::new();
        if (&mut r).take(MAX_LINE).read_line(&mut line).await? == 0 {
            return Ok(());
        }
        let req = match serde_json::from_str(&line) {
            Ok(Request::Watch) => {
                let mut ev = d.events();
                write(&mut w, &Reply { ok: true, ..Default::default() }).await?;
                loop {
                    // also ends when the window goes away without a word
                    tokio::select! {
                        e = ev.recv() => match e {
                            Ok(e) => write(&mut w, &e).await?,
                            Err(RecvError::Lagged(_)) => {}
                            Err(RecvError::Closed) => return Ok(()),
                        },
                        x = r.read_u8() => { x?; }
                    }
                }
            }
            Ok(req) => run(&d, req).await,
            Err(e) => Err(e.into()),
        };
        let rep = req.unwrap_or_else(|e| Reply { error: Some(format!("{e:#}")), ..Default::default() });
        write(&mut w, &rep).await?;
    }
}

/// a number the phone may call: digits with + and spaces, 3 to 15 digits, nothing that dials codes (* #)
pub fn dialable(n: &str) -> Result<String> {
    let n = n.trim();
    let digits = n.chars().filter(char::is_ascii_digit).count();
    if !(3..=15).contains(&digits)
        || !n.chars().all(|c| c.is_ascii_digit() || " +-()".contains(c))
        || n.rfind('+').is_some_and(|i| i > 0)
    {
        bail!("that is not a phone number");
    }
    Ok(n.into())
}

async fn write<T: Serialize>(w: &mut (impl AsyncWriteExt + Unpin), v: &T) -> Result<()> {
    let mut b = serde_json::to_vec(v)?;
    b.push(b'\n');
    Ok(w.write_all(&b).await?)
}

async fn run(d: &Arc<Daemon>, r: Request) -> Result<Reply> {
    let mut out = Reply { ok: true, ..Default::default() };
    match r {
        Request::Status => out.devices = Some(d.status()),
        Request::Pair => out.pairing = Some(d.open_pairing(PAIRING_TIME)),
        Request::CancelPairing => d.close_pairing(),
        Request::Answer { yes } => d.answer(yes)?,
        Request::Allow { device, cap, on } => d.allow(&d.find(&device)?, cap, on)?,
        Request::Unpair { device } => d.unpair(&d.find(&device)?)?,
        Request::SmsThreads { device, before } => {
            let fp = d.find(&device)?;
            out.answer = Some(d.ask(&fp, Capability::Sms, |req| Msg::SmsList { req, limit: 40, before }).await?);
        }
        Request::SmsMessages { device, thread, before } => {
            let fp = d.find(&device)?;
            out.answer = Some(d.ask(&fp, Capability::Sms, |req| Msg::SmsRead { req, thread, limit: 50, before }).await?);
        }
        Request::SmsPhotos { device, mut addresses } => {
            let fp = d.find(&device)?;
            addresses.truncate(5);
            out.answer = Some(d.ask(&fp, Capability::Sms, |req| Msg::SmsPhotos { req, addresses }).await?);
        }
        Request::SmsSend { device, to, text } => {
            let fp = d.find(&device)?;
            if text.trim().is_empty() || text.chars().count() > 2000 {
                bail!("a text has 1 to 2000 characters");
            }
            out.answer = Some(d.ask(&fp, Capability::Sms, |req| Msg::SmsSend { req, to, text }).await?);
        }
        Request::Call { device, what, number } => {
            let fp = d.find(&device)?;
            let number = match what {
                CallAction::Dial => Some(dialable(number.as_deref().unwrap_or(""))?),
                _ => None,
            };
            out.answer = Some(d.ask(&fp, Capability::Calls, |req| Msg::CallDo { req, what, number }).await?);
        }
        Request::Watch => unreachable!("handled by client()"),
    }
    Ok(out)
}
