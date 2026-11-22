// SPDX-License-Identifier: GPL-3.0-or-later
//! The windows' end of pairlumed's local socket. Everything slow is done on another thread.
use anyhow::{Context, Result, bail};
use cxx_qt::{CxxQtType, Threading};
use cxx_qt_lib::QString;
use pairlumed::{
    config_dir,
    control::{Reply, Request},
    socket_path,
};
use std::{
    io::{BufRead, BufReader, Write},
    os::unix::net::UnixStream,
    pin::Pin,
    time::Duration,
};

#[cxx_qt::bridge]
pub mod qobject {
    unsafe extern "C++" {
        include!("cxx-qt-lib/qstring.h");
        type QString = cxx_qt_lib::QString;
    }
    extern "RustQt" {
        #[qobject]
        #[qml_element]
        #[qproperty(bool, connected)]
        #[qproperty(QString, colors)]
        type Service = super::ServiceRust;

        /// something happened in pairlumed (one JSON, see pairlumed::Event)
        #[qsignal]
        fn happened(self: Pin<&mut Service>, json: QString);
        /// pairlumed said no, or is not there
        #[qsignal]
        fn failed(self: Pin<&mut Service>, why: QString);

        #[qinvokable]
        fn start(self: Pin<&mut Service>);
        /// a request (one JSON, see pairlumed::control::Request)
        #[qinvokable]
        fn ask(self: Pin<&mut Service>, json: QString);
        /// the same, and the answer comes as `replied` with the same tag (an error: with `why` in it)
        #[qinvokable]
        #[cxx_name = "askFor"]
        fn ask_for(self: Pin<&mut Service>, tag: QString, json: QString);
        #[qsignal]
        fn replied(self: Pin<&mut Service>, tag: QString, json: QString);
        /// the squares of a QR code: one line per row, 0 and 1
        #[qinvokable]
        fn qr(self: &Service, text: QString) -> QString;
    }
    impl cxx_qt::Threading for Service {}
}

#[derive(Default)]
pub struct ServiceRust {
    connected: bool,
    colors: QString,
    started: bool,
}

fn connect() -> Result<BufReader<UnixStream>> {
    Ok(BufReader::new(UnixStream::connect(socket_path()?).context("Pairlume's service is not running")?))
}

fn request(s: &mut BufReader<UnixStream>, json: &str) -> Result<Reply> {
    s.get_mut().write_all(format!("{json}\n").as_bytes())?;
    let mut l = String::new();
    s.read_line(&mut l)?;
    let r: Reply = serde_json::from_str(&l)?;
    match r.error {
        Some(e) => bail!(e),
        None => Ok(r),
    }
}

impl qobject::Service {
    fn start(mut self: Pin<&mut Self>) {
        if std::mem::replace(&mut self.as_mut().rust_mut().started, true) {
            return;
        }
        let qt = self.as_ref().qt_thread();
        std::thread::spawn(move || {
            let watch = || -> Result<()> {
                let mut s = connect()?;
                request(&mut s, &serde_json::to_string(&Request::Watch)?)?;
                qt.queue(|o| o.set_connected(true)).ok().context("the window is gone")?;
                loop {
                    let mut l = String::new();
                    if s.read_line(&mut l)? == 0 {
                        return Ok(());
                    }
                    let l = QString::from(l.trim());
                    qt.queue(move |o| o.happened(l)).ok().context("the window is gone")?;
                }
            };
            loop {
                let _ = watch();
                if qt.queue(|o| o.set_connected(false)).is_err() {
                    return;
                }
                std::thread::sleep(Duration::from_secs(1));
            }
        });
        // colors.json is written by matugen (contrib/matugen): the window follows the wallpaper
        let qt = self.qt_thread();
        std::thread::spawn(move || {
            let Ok(path) = config_dir().map(|d| d.join("colors.json")) else { return };
            let mut last = None;
            loop {
                let now = std::fs::metadata(&path).and_then(|m| m.modified()).ok();
                if now.is_some() && now != last {
                    last = now;
                    let text = QString::from(std::fs::read_to_string(&path).unwrap_or_default().as_str());
                    if qt.queue(move |o| o.set_colors(text)).is_err() {
                        return;
                    }
                }
                std::thread::sleep(Duration::from_millis(700));
            }
        });
    }

    fn ask(self: Pin<&mut Self>, json: QString) {
        let qt = self.qt_thread();
        std::thread::spawn(move || {
            if let Err(e) = connect().and_then(|mut s| request(&mut s, &String::from(&json))) {
                let why = QString::from(format!("{e:#}").as_str());
                let _ = qt.queue(move |o| o.failed(why));
            }
        });
    }

    fn ask_for(self: Pin<&mut Self>, tag: QString, json: QString) {
        let qt = self.qt_thread();
        std::thread::spawn(move || {
            let r = connect().and_then(|mut s| request(&mut s, &String::from(&json)));
            let text = match r {
                Ok(r) => serde_json::to_string(&r).unwrap_or_default(),
                Err(e) => serde_json::json!({ "ok": false, "why": format!("{e:#}") }).to_string(),
            };
            let text = QString::from(text.as_str());
            let _ = qt.queue(move |o| o.replied(tag, text));
        });
    }

    fn qr(&self, text: QString) -> QString {
        let Ok(c) = qrcode::QrCode::with_error_correction_level(String::from(&text), qrcode::EcLevel::L) else {
            return QString::default();
        };
        let bits: Vec<char> = c.to_colors().iter().map(|x| if *x == qrcode::Color::Dark { '1' } else { '0' }).collect();
        let rows: Vec<String> = bits.chunks(c.width()).map(|r| r.iter().collect()).collect();
        QString::from(rows.join("\n").as_str())
    }
}
