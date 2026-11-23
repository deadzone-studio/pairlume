// SPDX-License-Identifier: GPL-3.0-or-later
//! Phones connect here.
use crate::{CallNow, Closed, Daemon, Event, Session};
use anyhow::{Context, Result, bail};
use pairlume_core::{
    PROTOCOL_VERSION,
    identity::Fingerprint,
    message::{CallState, Msg, PairMode},
    pairing::{self, Ends},
    store::clean_name,
    tls,
    wire::{STEP, recv, recv_step, send},
};
use std::{net::SocketAddr, sync::Arc, time::Duration};
use tokio::{
    net::{TcpListener, TcpStream},
    sync::{Semaphore, mpsc, oneshot},
};
use tokio_rustls::{TlsAcceptor, server::TlsStream};
use tracing::{debug, info};

type Stream = TlsStream<TcpStream>;

/// a phone says something at least every 15 s (Ping)
const QUIET: Duration = Duration::from_secs(45);
/// connections that have not shown yet who they are
const STRANGERS: usize = 16;

/// accepts until the task is stopped
pub async fn serve(d: Arc<Daemon>, l: TcpListener) -> Result<()> {
    let gate = {
        let d = d.clone();
        Arc::new(move |fp: &Fingerprint| d.lock().store.get(fp).is_some() || d.pairing_open())
    };
    let tls = TlsAcceptor::from(tls::server_config(&d.identity, gate)?);
    let strangers = Arc::new(Semaphore::new(STRANGERS));
    loop {
        let (tcp, from) = match l.accept().await {
            Ok(x) => x,
            Err(e) => {
                debug!("accept: {e}");
                tokio::time::sleep(Duration::from_millis(100)).await;
                continue;
            }
        };
        let Ok(place) = strangers.clone().try_acquire_owned() else {
            debug!("too many strangers, {from} is turned away");
            continue;
        };
        let (d, tls) = (d.clone(), tls.clone());
        tokio::spawn(async move {
            let r = async {
                let (s, fp, name) = greet(&d, &tls, tcp).await?;
                let known = d.lock().store.get(&fp).is_some();
                if known {
                    drop(place);
                    return start_session(&d, s, fp);
                }
                pair(&d, s, fp, name, place).await
            };
            if let Err(e) = r.await {
                debug!("{from}: {e:#}");
            }
        });
    }
}

async fn greet(d: &Daemon, tls: &TlsAcceptor, tcp: TcpStream) -> Result<(Stream, Fingerprint, String)> {
    tcp.set_nodelay(true)?;
    let mut s = tokio::time::timeout(STEP, tls.accept(tcp)).await.context("handshake took too long")??;
    let fp = tls::peer(s.get_ref().1.peer_certificates())?;
    let (v, name) = match recv_step(&mut s, STEP).await? {
        Msg::Hello { v, name } => (v, clean_name(&name)),
        m => bail!("expected a hello, got {m:?}"),
    };
    send(&mut s, &Msg::Hello { v: PROTOCOL_VERSION, name: d.name.clone() }).await?;
    if v != PROTOCOL_VERSION {
        bail!("the phone speaks protocol {v}");
    }
    Ok((s, fp, name))
}

// ---------- pairing ----------
async fn pair(
    d: &Arc<Daemon>,
    mut s: Stream,
    fp: Fingerprint,
    name: String,
    place: tokio::sync::OwnedSemaphorePermit,
) -> Result<()> {
    let mode = match recv_step(&mut s, STEP).await? {
        Msg::PairStart { mode } => mode,
        m => bail!("expected pairing, got {m:?}"),
    };
    let taken = {
        let mut g = d.lock();
        match g.window.as_mut() {
            Some(w) if !w.busy && w.until > std::time::Instant::now() => {
                w.busy = true;
                Some((w.number, w.digits.clone(), w.secret))
            }
            _ => None,
        }
    };
    let Some((number, digits, secret)) = taken else {
        let _ = send(&mut s, &Msg::Fail { reason: "not pairing now".into() }).await;
        bail!("not pairing now");
    };
    let e = Ends { computer: d.identity.fingerprint, phone: fp };
    let r = match mode {
        PairMode::Qr => pairing::qr_computer(&mut s, e, &secret).await,
        PairMode::Digits => pairing::digits_computer(&mut s, e, &digits).await,
        PairMode::Shake => {
            let (d, name) = (d.clone(), name.clone());
            let ask = |code| async move {
                let (tx, rx) = oneshot::channel();
                match d.lock().window.as_mut() {
                    Some(w) if w.number == number => w.answer = Some(tx),
                    _ => return false,
                }
                d.tell(Event::PairingCode { name, code });
                rx.await.unwrap_or(false)
            };
            pairing::shake_computer(&mut s, e, ask).await
        }
    };
    // stopped or opened anew meanwhile: whatever was proved, it was for a code that is gone
    let still = d.lock().window.as_ref().is_some_and(|w| w.number == number);
    match r {
        Ok(()) if still => {
            d.lock().store.add(fp, &name)?;
            info!("paired with {name}");
            d.tell(Event::Paired { id: fp, name });
            d.close_window(Some(number), Closed::Paired);
            drop(place);
            start_session(d, s, fp)
        }
        r => {
            let why = r.err().unwrap_or_else(|| anyhow::anyhow!("pairing was stopped"));
            let _ = send(&mut s, &Msg::Fail { reason: "pairing failed".into() }).await;
            // the digits and the secret had their one try
            info!("pairing with {name} failed: {why:#}");
            d.close_window(Some(number), Closed::Failed);
            Err(why)
        }
    }
}

// ---------- a paired phone ----------
fn start_session(d: &Arc<Daemon>, s: Stream, fp: Fingerprint) -> Result<()> {
    let (out, rx) = mpsc::channel(32);
    let mut g = d.lock();
    let dev = g.store.get(&fp).context("unpaired meanwhile")?.clone();
    g.counter += 1;
    let number = g.counter;
    out.try_send(Msg::Allowed { caps: dev.allowed }).expect("an empty queue");
    let task = tokio::spawn(run_session(d.clone(), s, fp, number, rx)).abort_handle();
    // the same phone again (it lost the Wi-Fi): the old connection goes
    if let Some(old) = g.sessions.insert(fp, Session { number, task, out, battery: None, asked: Default::default(), call: None })
    {
        old.task.abort();
    }
    drop(g);
    d.tell(Event::Online { id: fp, name: dev.name });
    Ok(())
}

async fn run_session(d: Arc<Daemon>, s: Stream, fp: Fingerprint, number: u64, mut rx: mpsc::Receiver<Msg>) {
    let (mut r, mut w) = tokio::io::split(s);
    let reader = async {
        loop {
            let m = tokio::time::timeout(QUIET, recv(&mut r)).await.context("the phone went quiet")??;
            handle(&d, fp, number, m)?;
        }
        #[allow(unreachable_code)]
        Ok::<(), anyhow::Error>(())
    };
    let writer = async {
        while let Some(m) = rx.recv().await {
            tokio::time::timeout(STEP, send(&mut w, &m)).await.context("the phone does not read")??;
        }
        Ok::<(), anyhow::Error>(())
    };
    let end = tokio::select! { x = reader => x, x = writer => x };
    if let Err(e) = end {
        debug!("{}: {e:#}", fp.short());
    }
    let mut g = d.lock();
    if g.sessions.get(&fp).is_some_and(|s| s.number == number) {
        g.sessions.remove(&fp);
        drop(g);
        d.tell(Event::Offline { id: fp });
    }
}

fn handle(d: &Daemon, fp: Fingerprint, number: u64, m: Msg) -> Result<()> {
    let mut g = d.lock();
    let allowed = match m.needs() {
        Some(cap) => g.store.get(&fp).is_some_and(|x| x.allowed.contains(&cap)),
        None => true,
    };
    let Some(s) = g.sessions.get_mut(&fp).filter(|s| s.number == number) else { bail!("an old connection") };
    // a full queue: the phone asks faster than it reads. It loses the answer, nobody waits for it
    if !allowed {
        let _ = s.out.try_send(Msg::Denied { cap: m.needs().expect("checked above") });
        return Ok(());
    }
    match m {
        Msg::Ping => {
            let _ = s.out.try_send(Msg::Pong);
        }
        Msg::Battery { percent, charging } => {
            let percent = percent.min(100);
            s.battery = Some((percent, charging));
            drop(g);
            d.tell(Event::Battery { id: fp, percent, charging });
        }
        // an answer nobody waits for any more is dropped
        m if m.answers().is_some() => {
            if let Some(tx) = m.answers().and_then(|req| s.asked.remove(&req)) {
                let _ = tx.send(m.clean());
            }
        }
        m @ Msg::SmsNew { .. } => {
            drop(g);
            if let Msg::SmsNew { thread, message } = m.clean() {
                d.tell(Event::Sms { id: fp, thread, message });
            }
        }
        m @ Msg::Call { .. } => {
            let m = m.clean();
            if let Msg::Call { state, number, name, .. } = &m {
                s.call =
                    (*state != CallState::Ended).then(|| CallNow { state: *state, number: number.clone(), name: name.clone() });
            }
            drop(g);
            if let Msg::Call { state, number, name, missed, png } = m {
                d.tell(Event::Call { id: fp, state, number, name, missed, png });
            }
        }
        Msg::Pong | Msg::Unknown => {}
        m => bail!("unexpected message: {m:?}"),
    }
    Ok(())
}

/// the address phones on this network reach us at (no packet is sent)
pub fn lan_addr(port: u16) -> Option<SocketAddr> {
    let s = std::net::UdpSocket::bind("0.0.0.0:0").ok()?;
    s.connect("192.0.2.1:9").ok()?;
    let ip = s.local_addr().ok()?.ip();
    (!ip.is_loopback() && !ip.is_unspecified()).then(|| SocketAddr::new(ip, port))
}
