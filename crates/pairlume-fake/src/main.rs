// SPDX-License-Identifier: GPL-3.0-or-later
mod call;
mod notif;
mod sms;

use anyhow::{Context, Result};
use clap::{Parser, Subcommand};
use pairlume_core::{
    client::{self, Link},
    identity::{Fingerprint, Identity},
    message::Msg,
    pairing::QrCode,
    store::Store,
    wire::{recv, send},
};
use std::{net::SocketAddr, path::PathBuf, sync::Arc, time::Duration};

/// A pretend phone: pairs with pairlumed and tells it about a battery that does not exist
#[derive(Parser)]
#[command(version)]
struct Args {
    /// where it keeps its identity
    #[arg(long)]
    dir: PathBuf,
    #[arg(long, default_value = "Fake phone")]
    name: String,
    #[command(subcommand)]
    cmd: Cmd,
}

#[derive(Subcommand)]
enum Cmd {
    /// as if it was shaken
    Shake {
        addr: SocketAddr,
        /// say yes to the code without asking
        #[arg(long)]
        yes: bool,
    },
    Digits {
        addr: SocketAddr,
        digits: String,
    },
    Qr {
        uri: String,
    },
    /// connect to the paired computer and stay
    Run {
        addr: SocketAddr,
        #[arg(long, default_value_t = 80)]
        battery: u8,
        /// stop after this many seconds
        #[arg(long)]
        seconds: Option<u64>,
        /// Emma calls after this many seconds, and rings for 12
        #[arg(long)]
        ring: Option<u64>,
        /// send three notifications after this many seconds
        #[arg(long)]
        notify: Option<u64>,
    },
}

async fn ask(code: String, yes: bool) -> bool {
    println!("Code on this phone: {code}");
    if yes {
        return true;
    }
    println!("The same on the computer? [y/N]");
    let line = tokio::task::spawn_blocking(|| {
        let mut l = String::new();
        std::io::stdin().read_line(&mut l).map(|_| l)
    });
    matches!(line.await, Ok(Ok(l)) if l.trim().eq_ignore_ascii_case("y"))
}

async fn stay(l: Link, battery: u8, seconds: Option<u64>, ring: Option<u64>, notify: Option<u64>) -> Result<()> {
    let (mut r, w) = tokio::io::split(l.stream);
    let w = Arc::new(tokio::sync::Mutex::new(w));
    let now = std::time::SystemTime::now().duration_since(std::time::UNIX_EPOCH)?.as_millis() as i64;
    let mut texts = sms::Sms::new(now);
    let calls = Arc::new(tokio::sync::Mutex::new(call::Calls::default()));
    let notifs = Arc::new(tokio::sync::Mutex::new(notif::Notifs::new(now)));
    if let Some(after) = notify {
        let (w, notifs) = (w.clone(), notifs.clone());
        tokio::spawn(async move {
            tokio::time::sleep(Duration::from_secs(after)).await;
            let all = notifs.lock().await.all();
            for m in all {
                let _ = send(&mut *w.lock().await, &m).await;
            }
        });
    }
    if let Some(after) = ring {
        let (w, calls) = (w.clone(), calls.clone());
        tokio::spawn(async move {
            tokio::time::sleep(Duration::from_secs(after)).await;
            let m = calls.lock().await.ring("+48 555 010 001", "Emma", Some(sms::emma()));
            let _ = send(&mut *w.lock().await, &m).await;
            tokio::time::sleep(Duration::from_secs(12)).await;
            let m = calls.lock().await.missed();
            if let Some(m) = m {
                let _ = send(&mut *w.lock().await, &m).await;
            }
        });
    }
    let read = async {
        loop {
            match recv(&mut r).await? {
                Msg::Pong => {}
                m @ (Msg::SmsList { .. } | Msg::SmsRead { .. } | Msg::SmsPhotos { .. } | Msg::SmsSend { .. }) => {
                    let (answer, later) = texts.answer(m);
                    if let Some(a) = answer {
                        send(&mut *w.lock().await, &a).await?;
                    }
                    if let Some(x) = later {
                        let w = w.clone();
                        tokio::spawn(async move {
                            tokio::time::sleep(Duration::from_millis(1500)).await;
                            let _ = send(&mut *w.lock().await, &x).await;
                        });
                    }
                }
                m @ Msg::NotifDo { .. } => {
                    let out = notifs.lock().await.answer(m);
                    for x in out {
                        send(&mut *w.lock().await, &x).await?;
                    }
                }
                m @ Msg::CallDo { .. } => {
                    let out = calls.lock().await.answer(m);
                    for x in out {
                        send(&mut *w.lock().await, &x).await?;
                    }
                }
                m => println!("{m:?}"),
            }
        }
        #[allow(unreachable_code)]
        Ok::<(), anyhow::Error>(())
    };
    let write = async {
        loop {
            {
                let mut w = w.lock().await;
                send(&mut *w, &Msg::Ping).await?;
                send(&mut *w, &Msg::Battery { percent: battery, charging: false }).await?;
            }
            tokio::time::sleep(Duration::from_secs(10)).await;
        }
        #[allow(unreachable_code)]
        Ok::<(), anyhow::Error>(())
    };
    let end = async {
        match seconds {
            Some(s) => tokio::time::sleep(Duration::from_secs(s)).await,
            None => std::future::pending().await,
        }
    };
    tokio::select! { x = read => x, x = write => x, () = end => Ok(()) }
}

#[tokio::main]
async fn main() -> Result<()> {
    let a = Args::parse();
    let id = Identity::load_or_create(&a.dir)?;
    let mut store = Store::open(&a.dir)?;
    let l = match a.cmd {
        Cmd::Shake { addr, yes } => client::pair_shake(&id, &a.name, addr, |c| ask(c, yes)).await?,
        Cmd::Digits { addr, digits } => client::pair_digits(&id, &a.name, addr, &digits).await?,
        Cmd::Qr { uri } => client::pair_qr(&id, &a.name, &QrCode::parse(&uri)?).await?,
        Cmd::Run { addr, battery, seconds, ring, notify } => {
            let known: Option<Fingerprint> = store.iter().next().map(|(f, _)| *f);
            let l = client::connect(&id, &a.name, addr, Some(known.context("not paired yet")?)).await?;
            println!("Connected to {}", l.name);
            return stay(l, battery, seconds, ring, notify).await;
        }
    };
    store.add(l.computer, &l.name)?;
    println!("Paired with {} ({})", l.name, l.computer.short());
    Ok(())
}
