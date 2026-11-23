// SPDX-License-Identifier: GPL-3.0-or-later
//! Bluetooth, so that the voice of a call can come to the computer: the computer is the phone's hands-free set.
//!
//! The phone asks over its paired link (`bt_pair`). For the next minute and a half, and only then, the computer may be
//! paired: its agent shows the code of Bluetooth on the screen and the person says whether the phone shows the same.
use crate::{Daemon, Event};
use anyhow::{Context, Result};
use bluer::agent::{Agent, AgentHandle, ReqError, RequestConfirmation};
use pairlume_core::identity::Fingerprint;
use std::{sync::Arc, time::Duration};
use tokio::sync::oneshot;
use tracing::{info, warn};

pub const WINDOW: Duration = Duration::from_secs(90);

#[derive(Default)]
pub struct Bt {
    /// the computer's Bluetooth address, when it has Bluetooth
    pub address: Option<String>,
    /// the phone that asked, and the number of its window
    waiting: Option<(Fingerprint, u64)>,
    number: u64,
    agent: Option<AgentHandle>,
    answer: Option<oneshot::Sender<bool>>,
}

fn lock(d: &Daemon) -> std::sync::MutexGuard<'_, Bt> {
    d.bt.lock().unwrap_or_else(|e| e.into_inner())
}

/// the address, once; nothing when there is no Bluetooth
pub async fn start(d: Arc<Daemon>) {
    let find = async {
        let s = bluer::Session::new().await?;
        let a = s.default_adapter().await?;
        anyhow::Ok(a.address().await?.to_string())
    };
    match find.await {
        Ok(addr) => lock(&d).address = Some(addr),
        Err(e) => info!("no Bluetooth: {e:#}"),
    }
}

/// a paired phone asks to be paired over Bluetooth too
pub async fn open(d: &Arc<Daemon>, fp: Fingerprint) -> Result<()> {
    // asked again while it is open: the same window
    if lock(d).waiting.is_some_and(|(f, _)| f == fp) {
        return Ok(());
    }
    let s = bluer::Session::new().await?;
    let adapter = s.default_adapter().await?;
    let number = {
        let mut b = lock(d);
        b.number += 1;
        b.waiting = Some((fp, b.number));
        b.number
    };
    let dd = d.clone();
    let agent = Agent {
        request_default: true,
        request_confirmation: Some(Box::new(move |r: RequestConfirmation| {
            let d = dd.clone();
            Box::pin(async move { confirm(&d, r).await })
        })),
        // the services of a device this computer paired with (hands-free): yes
        authorize_service: Some(Box::new(|_| Box::pin(async { Ok(()) }))),
        ..Default::default()
    };
    let handle = s.register_agent(agent).await.context("Bluetooth did not take the agent")?;
    adapter.set_pairable_timeout(WINDOW.as_secs() as u32).await?;
    adapter.set_pairable(true).await?;
    // a computer without any paired device does not even answer a phone that knows its address
    adapter.set_discoverable_timeout(WINDOW.as_secs() as u32).await?;
    adapter.set_discoverable(true).await?;
    lock(d).agent = Some(handle);
    info!("Bluetooth pairing open for {}", fp.short());
    let d = d.clone();
    tokio::spawn(async move {
        tokio::time::sleep(WINDOW).await;
        close(&d, number).await;
    });
    Ok(())
}

async fn close(d: &Daemon, number: u64) {
    let agent = {
        let mut b = lock(d);
        if b.waiting.is_none_or(|(_, n)| n != number) {
            return;
        }
        b.waiting = None;
        b.answer = None;
        b.agent.take()
    };
    drop(agent);
    if let Ok(a) = async { bluer::Session::new().await?.default_adapter().await }.await {
        let _ = a.set_pairable(false).await;
        let _ = a.set_discoverable(false).await;
    }
}

async fn confirm(d: &Arc<Daemon>, r: RequestConfirmation) -> Result<(), ReqError> {
    let (tx, rx) = oneshot::channel();
    let (fp, number) = {
        let mut b = lock(d);
        let Some(w) = b.waiting else { return Err(ReqError::Rejected) };
        b.answer = Some(tx);
        w
    };
    let name = async {
        let s = bluer::Session::new().await?;
        s.adapter(&r.adapter)?.device(r.device)?.alias().await
    }
    .await
    .unwrap_or_else(|_| r.device.to_string());
    info!("Bluetooth code for {name}");
    d.tell(Event::BtCode { id: fp, name: pairlume_core::store::clean_name(&name), code: format!("{:06}", r.passkey) });
    let yes = tokio::time::timeout(Duration::from_secs(60), rx).await.ok().and_then(Result::ok).unwrap_or(false);
    d.tell(Event::BtDone { id: fp, ok: yes });
    if !yes {
        close(d, number).await;
        return Err(ReqError::Rejected);
    }
    let (d, device, adapter) = (d.clone(), r.device, r.adapter);
    // trusted, so that it connects again by itself; then the window can go
    tokio::spawn(async move {
        tokio::time::sleep(Duration::from_secs(4)).await;
        let trust = async { bluer::Session::new().await?.adapter(&adapter)?.device(device)?.set_trusted(true).await };
        if let Err(e) = trust.await {
            warn!("Bluetooth: {e:#}");
        }
        close(&d, number).await;
    });
    Ok(())
}

/// the person at the computer says whether the codes are the same
pub fn answer(d: &Daemon, yes: bool) -> Result<()> {
    lock(d).answer.take().context("no phone waits for a Bluetooth answer")?.send(yes).ok().context("too late")
}
