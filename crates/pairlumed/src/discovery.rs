// SPDX-License-Identifier: GPL-3.0-or-later
//! Lets phones on the same network find this computer (mDNS). It only says that Pairlume is here and whether it is
//! pairing: the fingerprint is checked on the connection itself.
use crate::{Daemon, Event};
use anyhow::Result;
use mdns_sd::{IfKind, ServiceDaemon, ServiceInfo};
use std::{sync::Arc, time::Duration};
use tokio::sync::broadcast::error::RecvError;
use tracing::warn;

pub const SERVICE: &str = "_pairlume._tcp.local.";

fn announce(m: &ServiceDaemon, d: &Daemon, port: u16) -> Result<()> {
    let id = d.identity.fingerprint.short();
    let pairing = if d.pairing_open() { "1" } else { "0" };
    let props = [("v", "1"), ("id", id.as_str()), ("name", d.name.as_str()), ("pairing", pairing)];
    let host = format!("pairlume-{id}.local.");
    let info = ServiceInfo::new(SERVICE, &format!("pairlume-{id}"), &host, "", port, &props[..])?.enable_addr_auto();
    Ok(m.register(info)?)
}

pub fn start() -> Result<ServiceDaemon> {
    let m = ServiceDaemon::new()?;
    // the service listens on IPv4, for other devices
    m.disable_interface(vec![IfKind::IPv6, IfKind::LoopbackV4])?;
    Ok(m)
}

/// phones hear that this computer is gone, instead of finding out
pub async fn stop(m: ServiceDaemon, d: &Daemon) {
    if let Ok(done) = m.unregister(&format!("pairlume-{}.{SERVICE}", d.identity.fingerprint.short())) {
        let _ = tokio::time::timeout(Duration::from_secs(1), done.recv_async()).await;
    }
    let _ = m.shutdown();
}

pub async fn run(m: ServiceDaemon, d: Arc<Daemon>, port: u16) -> Result<()> {
    let mut ev = d.events();
    announce(&m, &d, port)?;
    loop {
        match ev.recv().await {
            Ok(Event::PairingOpen { .. } | Event::PairingClosed { .. }) | Err(RecvError::Lagged(_)) => {
                if let Err(e) = announce(&m, &d, port) {
                    warn!("mDNS: {e:#}");
                }
            }
            Ok(_) => {}
            Err(RecvError::Closed) => return Ok(()),
        }
    }
}
