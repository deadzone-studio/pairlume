// SPDX-License-Identifier: GPL-3.0-or-later
use anyhow::{Context, Result};
use clap::Parser;
use pairlumed::{Daemon, config_dir, control, discovery, server, socket_path};
use tokio::net::TcpListener;
use tracing::{info, warn};

/// Pairlume's service: keeps the connection to your phones
#[derive(Parser)]
#[command(version)]
struct Args {
    /// TCP port phones connect to
    #[arg(long, default_value_t = pairlume_core::DEFAULT_PORT)]
    port: u16,
    /// listen only here (default: every IPv4 address)
    #[arg(long, default_value = "0.0.0.0")]
    listen: std::net::IpAddr,
    /// how phones see this computer (default: its host name)
    #[arg(long)]
    name: Option<String>,
    /// do not announce this computer on the network
    #[arg(long)]
    no_mdns: bool,
}

#[tokio::main]
async fn main() -> Result<()> {
    let a = Args::parse();
    tracing_subscriber::fmt()
        .with_env_filter(tracing_subscriber::EnvFilter::try_from_default_env().unwrap_or_else(|_| "info".into()))
        .init();
    let host = std::fs::read_to_string("/proc/sys/kernel/hostname").unwrap_or_default();
    let d = Daemon::open(&config_dir()?, a.name.as_deref().unwrap_or(host.trim()))?;
    let sock = socket_path()?;
    let ctl = control::listen(&sock)?;
    let tcp = TcpListener::bind((a.listen, a.port)).await.with_context(|| format!("port {} is taken", a.port))?;
    let at = tcp.local_addr()?;
    d.set_addr(if at.ip().is_unspecified() { server::lan_addr(at.port()) } else { Some(at) });
    info!("{} ({}) on {at}", d.name, d.identity.fingerprint.short());
    let mdns = if a.no_mdns { None } else { discovery::start().inspect_err(|e| warn!("mDNS: {e:#}")).ok() };
    if let Some(m) = mdns.clone() {
        let d = d.clone();
        tokio::spawn(async move {
            if let Err(e) = discovery::run(m, d, at.port()).await {
                warn!("phones cannot find this computer by themselves: {e:#}");
            }
        });
    }
    tokio::spawn(pairlumed::bluetooth::start(d.clone()));
    let mut term = tokio::signal::unix::signal(tokio::signal::unix::SignalKind::terminate())?;
    let r = tokio::select! {
        r = server::serve(d.clone(), tcp) => r,
        r = control::serve(d.clone(), ctl) => r,
        _ = tokio::signal::ctrl_c() => Ok(()),
        _ = term.recv() => Ok(()),
    };
    let _ = std::fs::remove_file(sock);
    if let Some(m) = mdns {
        discovery::stop(m, &d).await;
    }
    r
}
