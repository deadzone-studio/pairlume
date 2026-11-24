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
    io::{BufRead, BufReader, Read, Write},
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
        /// the compositor blurs what is behind our windows
        #[qproperty(bool, blurred)]
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
        /// one window of each kind: true when this one is it. Otherwise the one there is gets `args` and this one should go
        #[qinvokable]
        fn claim(self: Pin<&mut Service>, kind: QString, args: QString) -> bool;
        /// another start of this kind of window, with its arguments (JSON list)
        #[qsignal]
        fn again(self: Pin<&mut Service>, args: QString);
        /// asks Hyprland to bring this window to the front
        #[qinvokable]
        fn front(self: &Service);
        /// the words of a language for the windows (JSON: English -> words), from share/lang
        #[qinvokable]
        fn words(self: &Service, code: QString) -> QString;
        /// the languages there are: JSON [[code, name in itself], ...]
        #[qinvokable]
        fn languages(self: &Service) -> QString;
        /// the language chosen in the settings, "" for the system's
        #[qinvokable]
        #[cxx_name = "chosenLanguage"]
        fn chosen_language(self: &Service) -> QString;
        #[qinvokable]
        #[cxx_name = "chooseLanguage"]
        fn choose_language(self: &Service, code: QString);
        /// for the installer: what is in the release folder and on this computer (JSON: version, installed, apk_url,
        /// phones on a cable)
        #[qinvokable]
        #[cxx_name = "setupInfo"]
        fn setup_info(self: &Service, from: QString) -> QString;
        /// runs install.sh of the release folder with these arguments (JSON list); its lines come as `said`, the end as
        /// `ended` with its exit code
        #[qinvokable]
        #[cxx_name = "runInstaller"]
        fn run_installer(self: Pin<&mut Service>, from: QString, args: QString);
        #[qsignal]
        fn said(self: Pin<&mut Service>, line: QString);
        #[qsignal]
        fn ended(self: Pin<&mut Service>, code: i32);
        /// starts another window of Pairlume (JSON list of arguments)
        #[qinvokable]
        fn open(self: &Service, args: QString);
        /// opens the texts window at the conversation with this number
        #[qinvokable]
        #[cxx_name = "writeTo"]
        fn write_to(self: &Service, address: QString);
    }
    impl cxx_qt::Threading for Service {}
}

/// share/lang: the words of every window, the phone app and the installer
const LANGUAGES: [(&str, &str); 11] = [
    ("en", include_str!("../../../share/lang/en.json")),
    ("pl", include_str!("../../../share/lang/pl.json")),
    ("szl", include_str!("../../../share/lang/szl.json")),
    ("csb", include_str!("../../../share/lang/csb.json")),
    ("de", include_str!("../../../share/lang/de.json")),
    ("es", include_str!("../../../share/lang/es.json")),
    ("fr", include_str!("../../../share/lang/fr.json")),
    ("it", include_str!("../../../share/lang/it.json")),
    ("pt", include_str!("../../../share/lang/pt.json")),
    ("uk", include_str!("../../../share/lang/uk.json")),
    ("cs", include_str!("../../../share/lang/cs.json")),
];

#[derive(Default)]
pub struct ServiceRust {
    connected: bool,
    colors: QString,
    blurred: bool,
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

/// Hyprland: is blur on, and may it blur our layers? Ordinary windows are blurred anyway. The rule lasts until Hyprland
/// reads its config again; nothing is written to anyone's config.
fn blur() -> bool {
    let run = |args: &[&str]| {
        let o = std::process::Command::new("hyprctl").args(args).output().ok()?;
        o.status.success().then(|| String::from_utf8_lossy(&o.stdout).trim().to_string())
    };
    if std::env::var_os("HYPRLAND_INSTANCE_SIGNATURE").is_none() {
        return false;
    }
    let on = run(&["getoption", "decoration:blur:enabled"]).is_some_and(|o| o.contains("true") || o.contains("int: 1"));
    let rule =
        r#"hl.layer_rule({ name = "pairlume-blur", match = { namespace = "pairlume" }, blur = true, ignore_alpha = 0.2 })"#;
    on && run(&["eval", rule]).is_some_and(|o| o == "ok")
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
        // the wallpaper's colors: our own file (contrib/matugen), else the palette a shell keeps. An open window follows
        let qt = self.as_ref().qt_thread();
        std::thread::spawn(move || {
            let home = std::env::var_os("HOME").map(std::path::PathBuf::from).unwrap_or_default();
            let mut files: Vec<_> = config_dir().map(|d| d.join("colors.json")).into_iter().collect();
            files.push(home.join(".config/rice/palette.json"));
            let mut last = None;
            loop {
                let now = files.iter().find_map(|f| Some((f.clone(), std::fs::metadata(f).and_then(|m| m.modified()).ok()?)));
                if now.is_some() && now != last {
                    if let Some(text) = now.as_ref().and_then(|(f, _)| std::fs::read_to_string(f).ok()) {
                        let text = QString::from(text.as_str());
                        if qt.queue(move |o| o.set_colors(text)).is_err() {
                            return;
                        }
                    }
                    last = now;
                }
                std::thread::sleep(Duration::from_millis(700));
            }
        });
        let qt = self.qt_thread();
        std::thread::spawn(move || {
            if blur() {
                let _ = qt.queue(|o| o.set_blurred(true));
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

    fn claim(self: Pin<&mut Self>, kind: QString, args: QString) -> bool {
        let kind: String = String::from(&kind).chars().filter(char::is_ascii_alphanumeric).collect();
        let Some(dir) = std::env::var_os("XDG_RUNTIME_DIR") else { return true };
        let path = std::path::PathBuf::from(dir).join(format!("pairlume-ui-{kind}.sock"));
        if let Ok(mut s) = UnixStream::connect(&path) {
            let _ = s.set_write_timeout(Some(Duration::from_secs(1)));
            if s.write_all(format!("{}\n", String::from(&args)).as_bytes()).is_ok() {
                return false;
            }
        }
        let _ = std::fs::remove_file(&path);
        let Ok(l) = std::os::unix::net::UnixListener::bind(&path) else { return true };
        let qt = self.qt_thread();
        std::thread::spawn(move || {
            for s in l.incoming().flatten() {
                let mut line = String::new();
                let _ = s.set_read_timeout(Some(Duration::from_secs(1)));
                if BufReader::new(s).take(4096).read_line(&mut line).is_ok() {
                    let line = QString::from(line.trim());
                    if qt.queue(move |o| o.again(line)).is_err() {
                        return;
                    }
                }
            }
        });
        true
    }

    fn front(&self) {
        let pid = format!("pid:{}", std::process::id());
        let _ = std::process::Command::new("hyprctl").args(["dispatch", "focuswindow", &pid]).output();
    }

    fn words(&self, code: QString) -> QString {
        let code = String::from(&code);
        let file = LANGUAGES.iter().find(|(c, _)| *c == code).map(|(_, f)| *f).unwrap_or("{}");
        let ui = serde_json::from_str::<serde_json::Value>(file).ok().and_then(|v| v.get("ui").cloned()).unwrap_or_default();
        QString::from(ui.to_string().as_str())
    }

    fn languages(&self) -> QString {
        let list: Vec<(String, String)> = LANGUAGES
            .iter()
            .map(|(c, f)| {
                let name =
                    serde_json::from_str::<serde_json::Value>(f).ok().and_then(|v| v.get("name")?.as_str().map(String::from));
                ((*c).to_string(), name.unwrap_or_else(|| (*c).to_string()))
            })
            .collect();
        QString::from(serde_json::to_string(&list).unwrap_or_default().as_str())
    }

    fn chosen_language(&self) -> QString {
        let v = config_dir().ok().and_then(|d| std::fs::read_to_string(d.join("ui.json")).ok());
        let code = v.and_then(|t| serde_json::from_str::<serde_json::Value>(&t).ok()?.get("lang")?.as_str().map(String::from));
        QString::from(code.filter(|c| LANGUAGES.iter().any(|(k, _)| k == c)).unwrap_or_default().as_str())
    }

    fn choose_language(&self, code: QString) {
        let code = String::from(&code);
        let Ok(dir) = config_dir() else { return };
        let path = dir.join("ui.json");
        let mut v = std::fs::read_to_string(&path)
            .ok()
            .and_then(|t| serde_json::from_str::<serde_json::Value>(&t).ok())
            .unwrap_or_else(|| serde_json::json!({}));
        if let Some(o) = v.as_object_mut() {
            if code.is_empty() {
                o.remove("lang");
            } else if LANGUAGES.iter().any(|(k, _)| *k == code) {
                o.insert("lang".into(), code.into());
            }
        }
        let _ = std::fs::create_dir_all(&dir);
        let tmp = path.with_extension("json.tmp");
        if std::fs::write(&tmp, v.to_string()).is_ok() {
            let _ = std::fs::rename(tmp, path);
        }
    }

    fn setup_info(&self, from: QString) -> QString {
        let from = std::path::PathBuf::from(String::from(&from));
        let version = std::fs::read_to_string(from.join("VERSION")).map(|v| v.trim().to_string()).unwrap_or_default();
        let home = std::env::var_os("HOME").map(std::path::PathBuf::from).unwrap_or_default();
        let have = home.join(".local/bin/pairlumed");
        let installed = std::process::Command::new(&have)
            .arg("--version")
            .output()
            .ok()
            .and_then(|o| String::from_utf8(o.stdout).ok())
            .and_then(|s| s.split_whitespace().nth(1).map(String::from));
        // phones on a cable, when adb is there and the release has the app
        let adb = ["adb".into(), home.join("Android/Sdk/platform-tools/adb")].into_iter().find(|a: &std::path::PathBuf| {
            std::process::Command::new(a).arg("version").output().is_ok_and(|o| o.status.success())
        });
        let phones: Vec<String> = match adb.filter(|_| from.join("Pairlume.apk").is_file()) {
            Some(a) => std::process::Command::new(a)
                .args(["devices", "-l"])
                .output()
                .map(|o| {
                    String::from_utf8_lossy(&o.stdout)
                        .lines()
                        .skip(1)
                        .filter(|l| l.split_whitespace().nth(1) == Some("device"))
                        .map(|l| {
                            l.split(" model:")
                                .nth(1)
                                .and_then(|m| m.split_whitespace().next())
                                .unwrap_or("phone")
                                .replace('_', " ")
                        })
                        .collect()
                })
                .unwrap_or_default(),
            None => vec![],
        };
        let url = format!("https://github.com/deadzone-studio/pairlume/releases/download/v{version}/Pairlume-{version}.apk");
        // a firewall that may keep phones out: ufw or firewalld running
        let active = |unit: &str| {
            std::process::Command::new("systemctl").args(["is-active", "--quiet", unit]).status().is_ok_and(|s| s.success())
        };
        let firewall = if active("ufw") {
            "sudo ufw allow 47321/tcp && sudo ufw allow 5353/udp"
        } else if active("firewalld") {
            "sudo firewall-cmd --permanent --add-port=47321/tcp --add-service=mdns && sudo firewall-cmd --reload"
        } else {
            ""
        };
        let v = serde_json::json!({ "version": version, "installed": installed, "apk_url": url, "phones": phones,
            "has_installer": from.join("install.sh").is_file(), "firewall": firewall });
        QString::from(v.to_string().as_str())
    }

    fn run_installer(self: Pin<&mut Self>, from: QString, args: QString) {
        let from = std::path::PathBuf::from(String::from(&from));
        let args: Vec<String> = serde_json::from_str(&String::from(&args)).unwrap_or_default();
        let qt = self.qt_thread();
        std::thread::spawn(move || {
            let child = std::process::Command::new("bash")
                .arg(from.join("install.sh"))
                .args(&args)
                .env("NO_COLOR", "1")
                .stdin(std::process::Stdio::null())
                .stdout(std::process::Stdio::piped())
                .stderr(std::process::Stdio::piped())
                .spawn();
            let mut child = match child {
                Ok(c) => c,
                Err(e) => {
                    let line = QString::from(format!("{e}").as_str());
                    let _ = qt.queue(move |o| o.said(line));
                    let _ = qt.queue(|o| o.ended(1));
                    return;
                }
            };
            // what goes wrong is said too
            if let Some(err) = child.stderr.take() {
                let qt = qt.clone();
                std::thread::spawn(move || {
                    for l in BufReader::new(err).lines().map_while(Result::ok) {
                        let line = QString::from(l.as_str());
                        if qt.queue(move |o| o.said(line)).is_err() {
                            return;
                        }
                    }
                });
            }
            if let Some(out) = child.stdout.take() {
                for l in BufReader::new(out).lines().map_while(Result::ok) {
                    // no colors in a window
                    let clean: String = l.replace("\u{1b}[1m", "").replace("\u{1b}[0m", "");
                    let line = QString::from(clean.as_str());
                    if qt.queue(move |o| o.said(line)).is_err() {
                        return;
                    }
                }
            }
            let code = child.wait().ok().and_then(|s| s.code()).unwrap_or(1);
            let _ = qt.queue(move |o| o.ended(code));
        });
    }

    fn open(&self, args: QString) {
        let args: Vec<String> = serde_json::from_str(&String::from(&args)).unwrap_or_default();
        if let Ok(me) = std::env::current_exe() {
            let _ = std::process::Command::new(me).args(args).spawn();
        }
    }

    fn write_to(&self, address: QString) {
        if let Ok(me) = std::env::current_exe() {
            let _ = std::process::Command::new(me).args(["messages", "--to", &String::from(&address)]).spawn();
        }
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
