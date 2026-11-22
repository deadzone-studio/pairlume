// SPDX-License-Identifier: GPL-3.0-or-later
//! The phone's side of a connection (the fake phone and the tests; the Android app does the same in Kotlin).
use crate::{
    PROTOCOL_VERSION,
    identity::{Fingerprint, Identity},
    message::Msg,
    pairing::{self, Ends, QrCode},
    tls,
    wire::{STEP, recv_step, send},
};
use anyhow::{Context, Result, bail};
use std::{future::Future, net::SocketAddr, sync::Arc};
use tokio::net::TcpStream;
use tokio_rustls::{TlsConnector, client::TlsStream};

pub type Stream = TlsStream<TcpStream>;

pub struct Link {
    pub stream: Stream,
    pub computer: Fingerprint,
    pub name: String,
}

/// `expect`: the computer has to be this one (None only while pairing)
pub async fn connect(id: &Identity, name: &str, addr: SocketAddr, expect: Option<Fingerprint>) -> Result<Link> {
    let gate: tls::Gate = Arc::new(move |fp| expect.is_none_or(|e| e == *fp));
    let tcp = tokio::time::timeout(STEP, TcpStream::connect(addr)).await.context("no answer")??;
    tcp.set_nodelay(true)?;
    let c = TlsConnector::from(tls::client_config(id, gate)?);
    let host = "pairlume".try_into().expect("a name");
    let mut stream = tokio::time::timeout(STEP, c.connect(host, tcp)).await.context("no answer")??;
    let computer = tls::peer(stream.get_ref().1.peer_certificates())?;
    send(&mut stream, &Msg::Hello { v: PROTOCOL_VERSION, name: name.into() }).await?;
    match recv_step(&mut stream, STEP).await? {
        Msg::Hello { v, .. } if v != PROTOCOL_VERSION => bail!("the computer speaks protocol {v}, this phone {PROTOCOL_VERSION}"),
        Msg::Hello { name, .. } => Ok(Link { stream, computer, name: crate::store::clean_name(&name) }),
        m => bail!("expected a hello, got {m:?}"),
    }
}

impl Link {
    fn ends(&self, id: &Identity) -> Ends {
        Ends { computer: self.computer, phone: id.fingerprint }
    }
}

pub async fn pair_shake<F, Fut>(id: &Identity, name: &str, addr: SocketAddr, ask: F) -> Result<Link>
where
    F: FnOnce(String) -> Fut,
    Fut: Future<Output = bool>,
{
    let mut l = connect(id, name, addr, None).await?;
    let e = l.ends(id);
    pairing::shake_phone(&mut l.stream, e, ask).await?;
    Ok(l)
}

pub async fn pair_digits(id: &Identity, name: &str, addr: SocketAddr, digits: &str) -> Result<Link> {
    let mut l = connect(id, name, addr, None).await?;
    let e = l.ends(id);
    pairing::digits_phone(&mut l.stream, e, digits).await?;
    Ok(l)
}

pub async fn pair_qr(id: &Identity, name: &str, qr: &QrCode) -> Result<Link> {
    let mut l = connect(id, name, qr.addr, Some(qr.fingerprint)).await?;
    let e = l.ends(id);
    pairing::qr_phone(&mut l.stream, e, &qr.secret).await?;
    Ok(l)
}
