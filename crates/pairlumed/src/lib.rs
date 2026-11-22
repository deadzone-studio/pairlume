// SPDX-License-Identifier: GPL-3.0-or-later
//! The service on the computer. Windows are other programs that talk to it through `control`.
pub mod control;
pub mod discovery;
pub mod server;

use anyhow::{Context, Result, bail};
use pairlume_core::{
    identity::{Fingerprint, Identity},
    message::{Capability, Msg},
    pairing::{self, QrCode},
    store::Store,
};
use serde::{Deserialize, Serialize};
use std::{
    collections::BTreeMap,
    net::SocketAddr,
    path::{Path, PathBuf},
    sync::{Arc, Mutex, MutexGuard},
    time::{Duration, Instant},
};
use tokio::{
    sync::{broadcast, mpsc, oneshot},
    task::AbortHandle,
};

pub const PAIRING_TIME: Duration = Duration::from_secs(120);

/// why a pairing window is gone; the windows have words for it, the log has the details
#[derive(Clone, Copy, Debug, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum Closed {
    Paired,
    Stopped,
    Expired,
    /// the code, the digits or the proof was wrong, or the phone went away
    Failed,
}

#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
#[serde(tag = "event", rename_all = "snake_case")]
pub enum Event {
    PairingOpen {
        digits: String,
        qr: Option<String>,
        seconds: u64,
    },
    PairingClosed {
        reason: Closed,
    },
    /// a shaken phone: does its screen show the same code?
    PairingCode {
        name: String,
        code: String,
    },
    Paired {
        id: Fingerprint,
        name: String,
    },
    Unpaired {
        id: Fingerprint,
    },
    Online {
        id: Fingerprint,
        name: String,
    },
    Offline {
        id: Fingerprint,
    },
    Battery {
        id: Fingerprint,
        percent: u8,
        charging: bool,
    },
    Allowed {
        id: Fingerprint,
        cap: Capability,
        on: bool,
    },
}

#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct DeviceStatus {
    pub id: Fingerprint,
    pub name: String,
    pub online: bool,
    pub battery: Option<(u8, bool)>,
    pub allowed: Vec<Capability>,
}

struct Session {
    /// tells this connection from a later one of the same phone
    number: u64,
    task: AbortHandle,
    out: mpsc::Sender<Msg>,
    battery: Option<(u8, bool)>,
}

/// the minutes in which an unknown phone may pair. Digits and secret are for one try
struct Window {
    until: Instant,
    number: u64,
    digits: String,
    secret: [u8; 16],
    /// one phone at a time
    busy: bool,
    answer: Option<oneshot::Sender<bool>>,
}

struct Inner {
    store: Store,
    sessions: BTreeMap<Fingerprint, Session>,
    window: Option<Window>,
    counter: u64,
}

pub struct Daemon {
    pub identity: Identity,
    pub name: String,
    inner: Mutex<Inner>,
    events: broadcast::Sender<Event>,
    addr: Mutex<Option<SocketAddr>>,
}

impl Daemon {
    pub fn open(dir: &Path, name: &str) -> Result<Arc<Self>> {
        Ok(Arc::new(Self {
            identity: Identity::load_or_create(dir)?,
            name: pairlume_core::store::clean_name(name),
            inner: Mutex::new(Inner { store: Store::open(dir)?, sessions: BTreeMap::new(), window: None, counter: 0 }),
            events: broadcast::channel(64).0,
            addr: Mutex::new(None),
        }))
    }

    fn lock(&self) -> MutexGuard<'_, Inner> {
        self.inner.lock().unwrap_or_else(|e| e.into_inner())
    }
    pub fn events(&self) -> broadcast::Receiver<Event> {
        self.events.subscribe()
    }
    fn tell(&self, e: Event) {
        let _ = self.events.send(e);
    }
    /// where phones reach us (for the QR code)
    pub fn set_addr(&self, a: Option<SocketAddr>) {
        *self.addr.lock().unwrap_or_else(|e| e.into_inner()) = a;
    }

    // ---------- pairing ----------
    pub fn open_pairing(self: &Arc<Self>, time: Duration) -> Event {
        let addr = *self.addr.lock().unwrap_or_else(|e| e.into_inner());
        let (digits, secret) = (pairing::random_digits(), pairing::random::<16>());
        let qr = addr.map(|addr| QrCode { fingerprint: self.identity.fingerprint, secret, addr }.uri());
        let mut g = self.lock();
        g.counter += 1;
        let number = g.counter;
        g.window =
            Some(Window { until: Instant::now() + time, number, digits: digits.clone(), secret, busy: false, answer: None });
        drop(g);
        let me = self.clone();
        tokio::spawn(async move {
            tokio::time::sleep(time).await;
            me.close_window(Some(number), Closed::Expired);
        });
        let e = Event::PairingOpen { digits, qr, seconds: time.as_secs() };
        self.tell(e.clone());
        e
    }
    pub fn close_pairing(&self) {
        self.close_window(None, Closed::Stopped);
    }
    fn close_window(&self, number: Option<u64>, reason: Closed) {
        let mut g = self.lock();
        if g.window.as_ref().is_some_and(|w| number.is_none_or(|n| n == w.number)) {
            g.window = None;
            drop(g);
            self.tell(Event::PairingClosed { reason });
        }
    }
    pub fn pairing_open(&self) -> bool {
        self.lock().window.as_ref().is_some_and(|w| w.until > Instant::now())
    }
    /// the person at the computer says whether the codes are the same
    pub fn answer(&self, yes: bool) -> Result<()> {
        let tx = self.lock().window.as_mut().and_then(|w| w.answer.take());
        tx.context("no phone is waiting for an answer")?.send(yes).ok().context("the phone is gone")
    }

    // ---------- devices ----------
    pub fn status(&self) -> Vec<DeviceStatus> {
        let g = self.lock();
        (g.store.iter())
            .map(|(fp, d)| {
                let s = g.sessions.get(fp);
                DeviceStatus {
                    id: *fp,
                    name: d.name.clone(),
                    online: s.is_some(),
                    battery: s.and_then(|s| s.battery),
                    allowed: d.allowed.iter().copied().collect(),
                }
            })
            .collect()
    }
    pub fn find(&self, who: &str) -> Result<Fingerprint> {
        self.lock().store.find(who)
    }
    pub fn unpair(&self, fp: &Fingerprint) -> Result<()> {
        let mut g = self.lock();
        let had = g.store.remove(fp)?;
        let s = g.sessions.remove(fp);
        drop(g);
        if let Some(s) = s {
            s.task.abort();
            self.tell(Event::Offline { id: *fp });
        }
        if !had {
            bail!("this device is not paired");
        }
        self.tell(Event::Unpaired { id: *fp });
        Ok(())
    }
    pub fn allow(&self, fp: &Fingerprint, cap: Capability, on: bool) -> Result<()> {
        let mut g = self.lock();
        g.store.set_allowed(fp, cap, on)?;
        let caps = g.store.get(fp).map(|d| d.allowed.clone()).unwrap_or_default();
        if let Some(s) = g.sessions.get_mut(fp) {
            if cap == Capability::Battery && !on {
                s.battery = None;
            }
            let _ = s.out.try_send(Msg::Allowed { caps });
        }
        drop(g);
        self.tell(Event::Allowed { id: *fp, cap, on });
        Ok(())
    }
}

/// ~/.config/pairlume, or PAIRLUME_DIR
pub fn config_dir() -> Result<PathBuf> {
    if let Some(d) = std::env::var_os("PAIRLUME_DIR") {
        return Ok(d.into());
    }
    let base = match std::env::var_os("XDG_CONFIG_HOME") {
        Some(d) => PathBuf::from(d),
        None => PathBuf::from(std::env::var_os("HOME").context("no HOME")?).join(".config"),
    };
    Ok(base.join("pairlume"))
}

pub fn socket_path() -> Result<PathBuf> {
    if let Some(s) = std::env::var_os("PAIRLUME_SOCKET") {
        return Ok(s.into());
    }
    let dir = std::env::var_os("XDG_RUNTIME_DIR").context("no XDG_RUNTIME_DIR: set PAIRLUME_SOCKET")?;
    Ok(PathBuf::from(dir).join("pairlume.sock"))
}
