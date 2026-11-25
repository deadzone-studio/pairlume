//! The "system" look: the phone's notifications handed to the desktop's own notifications
//! (org.freedesktop.Notifications, the shell draws them). One thread keeps the session bus: it shows, updates and
//! closes them, and tells which button was pressed.

use dbus::arg::{PropMap, RefArg, Variant};
use dbus::blocking::Connection;
use dbus::message::MatchRule;
use std::collections::HashMap;
use std::path::PathBuf;
use std::sync::mpsc;
use std::time::Duration;

const DEST: &str = "org.freedesktop.Notifications";
const PATH: &str = "/org/freedesktop/Notifications";

/// one notification of the phone, as the shell gets it
pub struct Show {
    pub key: String,
    pub app: String,
    pub app_name: String,
    pub title: String,
    pub text: String,
    /// the app's icon, PNG in base64, when the computer has it
    pub icon: String,
    /// (name, label): the name comes back when it is pressed
    pub actions: Vec<(String, String)>,
    /// 0 to 100, for a bar
    pub value: Option<i32>,
}

pub enum Cmd {
    Show(Show),
    Close(String),
}

/// what comes back: the key of the notification and the name of the pressed button
pub type Pressed = Box<dyn Fn(String, String) + Send>;

/// starts the thread; commands go into the returned sender
pub fn start(pressed: Pressed) -> mpsc::Sender<Cmd> {
    let (tx, rx) = mpsc::channel::<Cmd>();
    std::thread::spawn(move || {
        if let Err(e) = run(&rx, &pressed) {
            eprintln!("pairlume-ui: desktop notifications: {e}");
        }
    });
    tx
}

enum Back {
    Action(u32, String),
    Closed(u32),
}

fn run(rx: &mpsc::Receiver<Cmd>, pressed: &Pressed) -> Result<(), dbus::Error> {
    let conn = Connection::new_session()?;
    let (btx, brx) = mpsc::channel::<Back>();
    let t = btx.clone();
    conn.add_match(MatchRule::new_signal(DEST, "ActionInvoked"), move |(id, action): (u32, String), _, _| {
        let _ = t.send(Back::Action(id, action));
        true
    })?;
    conn.add_match(MatchRule::new_signal(DEST, "NotificationClosed"), move |(id, _why): (u32, u32), _, _| {
        let _ = btx.send(Back::Closed(id));
        true
    })?;
    // key of the phone -> id of the desktop, and back
    let mut ids: HashMap<String, u32> = HashMap::new();
    loop {
        conn.process(Duration::from_millis(150))?;
        while let Ok(b) = brx.try_recv() {
            match b {
                Back::Action(id, action) => {
                    if let Some(key) = ids.iter().find(|(_, v)| **v == id).map(|(k, _)| k.clone()) {
                        pressed(key, action);
                    }
                }
                Back::Closed(id) => ids.retain(|_, v| *v != id),
            }
        }
        loop {
            match rx.try_recv() {
                Ok(Cmd::Show(s)) => {
                    let replaces = ids.get(&s.key).copied().unwrap_or(0);
                    if let Ok(id) = notify(&conn, &s, replaces) {
                        ids.insert(s.key, id);
                    }
                }
                Ok(Cmd::Close(key)) => {
                    if let Some(id) = ids.remove(&key) {
                        let p = conn.with_proxy(DEST, PATH, Duration::from_secs(2));
                        let _: Result<(), _> = p.method_call(DEST, "CloseNotification", (id,));
                    }
                }
                Err(mpsc::TryRecvError::Empty) => break,
                Err(mpsc::TryRecvError::Disconnected) => return Ok(()),
            }
        }
    }
}

fn notify(conn: &Connection, s: &Show, replaces: u32) -> Result<u32, dbus::Error> {
    let mut hints = PropMap::new();
    hints.insert("desktop-entry".into(), Variant(Box::new("io.github.m4rtwy.pairlume".to_string()) as Box<dyn RefArg>));
    if let Some(v) = s.value {
        hints.insert("value".into(), Variant(Box::new(v.clamp(0, 100)) as Box<dyn RefArg>));
    }
    let icon = icon_file(&s.app, &s.icon)
        .map(|p| p.to_string_lossy().into_owned())
        .unwrap_or_else(|| "io.github.m4rtwy.pairlume".into());
    let actions: Vec<&str> = s.actions.iter().flat_map(|(k, l)| [k.as_str(), l.as_str()]).collect();
    // shown until the shell itself puts it away; a bar that moves keeps coming back
    let p = conn.with_proxy(DEST, PATH, Duration::from_secs(3));
    let (id,): (u32,) = p.method_call(
        DEST,
        "Notify",
        (s.app_name.as_str(), replaces, icon, s.title.as_str(), s.text.as_str(), actions, hints, -1i32),
    )?;
    Ok(id)
}

/// the shell wants a file for an icon: ~/.cache/pairlume/icons/<app>.png, written once
fn icon_file(app: &str, b64: &str) -> Option<PathBuf> {
    if b64.is_empty() || app.is_empty() || !app.chars().all(|c| c.is_ascii_alphanumeric() || c == '.' || c == '_') {
        return None;
    }
    let base = std::env::var_os("XDG_CACHE_HOME")
        .map(PathBuf::from)
        .or_else(|| std::env::var_os("HOME").map(|h| PathBuf::from(h).join(".cache")))?;
    let dir = base.join("pairlume/icons");
    let path = dir.join(format!("{app}.png"));
    if !path.is_file() {
        let png = unbase64(b64)?;
        std::fs::create_dir_all(&dir).ok()?;
        std::fs::write(&path, png).ok()?;
    }
    Some(path)
}

fn unbase64(s: &str) -> Option<Vec<u8>> {
    let val = |c: u8| -> Option<u32> {
        Some(match c {
            b'A'..=b'Z' => c - b'A',
            b'a'..=b'z' => c - b'a' + 26,
            b'0'..=b'9' => c - b'0' + 52,
            b'+' => 62,
            b'/' => 63,
            _ => return None,
        } as u32)
    };
    let bytes: Vec<u8> = s.bytes().filter(|c| !c.is_ascii_whitespace() && *c != b'=').collect();
    let mut out = Vec::with_capacity(bytes.len() * 3 / 4);
    for chunk in bytes.chunks(4) {
        let mut n = 0u32;
        for (i, c) in chunk.iter().enumerate() {
            n |= val(*c)? << (18 - 6 * i);
        }
        out.push((n >> 16) as u8);
        if chunk.len() > 2 {
            out.push((n >> 8) as u8);
        }
        if chunk.len() > 3 {
            out.push(n as u8);
        }
    }
    Some(out)
}

#[cfg(test)]
mod tests {
    #[test]
    fn base64_comes_back() {
        assert_eq!(super::unbase64("UGFpcmx1bWU=").unwrap(), b"Pairlume");
        assert_eq!(super::unbase64("aGk").unwrap(), b"hi");
        assert!(super::unbase64("a$b").is_none());
    }
}
