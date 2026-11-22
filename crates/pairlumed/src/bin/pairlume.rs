// SPDX-License-Identifier: GPL-3.0-or-later
use anyhow::{Context, Result, bail};
use clap::{Parser, Subcommand};
use pairlume_core::message::Capability;
use pairlumed::{
    Closed, Event,
    control::{Reply, Request},
    socket_path,
};
use std::{
    io::{BufRead, BufReader, Write},
    os::unix::net::UnixStream,
};

/// Your phone and your desktop as one. This is the command line of pairlumed
#[derive(Parser)]
#[command(version)]
struct Args {
    #[command(subcommand)]
    cmd: Cmd,
}

#[derive(Subcommand)]
enum Cmd {
    /// paired phones, their battery and what they may do
    Status,
    /// pair a phone: shake it, scan the code or type the digits
    Pair {
        /// do not draw the QR code
        #[arg(long)]
        no_qr: bool,
    },
    /// let a phone use something: battery, sms, calls, notifications, files, clipboard, screen, camera
    Allow { device: String, what: Capability },
    /// take it back
    Deny { device: String, what: Capability },
    /// forget a phone
    Unpair { device: String },
    /// print what happens, one JSON per line
    Watch,
}

struct Link(BufReader<UnixStream>);

impl Link {
    fn new() -> Result<Self> {
        let s = UnixStream::connect(socket_path()?).context("pairlumed is not running")?;
        Ok(Self(BufReader::new(s)))
    }
    fn ask(&mut self, r: &Request) -> Result<Reply> {
        let mut b = serde_json::to_vec(r)?;
        b.push(b'\n');
        self.0.get_mut().write_all(&b)?;
        let rep: Reply = serde_json::from_str(&self.line()?)?;
        match rep.error {
            Some(e) => bail!(e),
            None => Ok(rep),
        }
    }
    fn line(&mut self) -> Result<String> {
        let mut l = String::new();
        if self.0.read_line(&mut l)? == 0 {
            bail!("pairlumed stopped");
        }
        Ok(l)
    }
}

fn qr(text: &str) -> Result<String> {
    let c = qrcode::QrCode::with_error_correction_level(text, qrcode::EcLevel::L).map_err(|e| anyhow::anyhow!("{e}"))?;
    Ok(c.render::<qrcode::render::unicode::Dense1x2>().quiet_zone(true).build())
}

fn spaced(code: &str) -> String {
    let (a, b) = code.split_at(code.len() / 2);
    format!("{a} {b}")
}

fn pair(no_qr: bool) -> Result<()> {
    // watching first, so nothing is missed
    let mut watch = Link::new()?;
    watch.ask(&Request::Watch)?;
    let mut l = Link::new()?;
    let Some(Event::PairingOpen { digits, qr: uri, seconds }) = l.ask(&Request::Pair)?.pairing else {
        bail!("no answer from pairlumed");
    };
    match uri {
        Some(u) if !no_qr => println!("{}", qr(&u)?),
        Some(u) => println!("{u}"),
        None => println!("(no network address: the QR code is not available)"),
    }
    println!("Shake the phone, scan the code, or type {} on the phone. {seconds} seconds.", spaced(&digits));
    loop {
        match serde_json::from_str(&watch.line()?)? {
            Event::PairingCode { name, code } => {
                print!("\n{name} wants to pair. Does it show {}? [y/N] ", spaced(&code));
                std::io::stdout().flush()?;
                let mut a = String::new();
                std::io::stdin().read_line(&mut a)?;
                let yes = matches!(a.trim().to_lowercase().as_str(), "y" | "yes" | "t" | "tak");
                // too late (the time is over): the next event says so
                if let Err(e) = l.ask(&Request::Answer { yes }) {
                    eprintln!("{e:#}");
                }
            }
            Event::Paired { name, .. } => {
                println!("Paired with {name}. Nothing is allowed yet: pairlume allow \"{name}\" battery");
                return Ok(());
            }
            Event::PairingClosed { reason } => bail!(match reason {
                Closed::Expired => "nobody paired in time",
                Closed::Stopped => "pairing was stopped",
                Closed::Paired | Closed::Failed => "the codes did not match, or the phone went away. Run it again for new ones",
            }),
            _ => {}
        }
    }
}

fn main() -> Result<()> {
    match Args::parse().cmd {
        Cmd::Pair { no_qr } => return pair(no_qr),
        Cmd::Status => {
            let devs = Link::new()?.ask(&Request::Status)?.devices.unwrap_or_default();
            if devs.is_empty() {
                println!("No phone is paired: pairlume pair");
            }
            for d in devs {
                let state = match (d.online, d.battery) {
                    (false, _) => "offline".to_string(),
                    (true, None) => "connected".into(),
                    (true, Some((p, c))) => format!("connected, {p} %{}", if c { ", charging" } else { "" }),
                };
                let may: Vec<_> = d.allowed.iter().map(ToString::to_string).collect();
                let may = if may.is_empty() { "nothing".into() } else { may.join(", ") };
                println!("{}  {}: {state}; may use: {may}", d.id.short(), d.name);
            }
        }
        Cmd::Allow { device, what } => drop(Link::new()?.ask(&Request::Allow { device, cap: what, on: true })?),
        Cmd::Deny { device, what } => drop(Link::new()?.ask(&Request::Allow { device, cap: what, on: false })?),
        Cmd::Unpair { device } => drop(Link::new()?.ask(&Request::Unpair { device })?),
        Cmd::Watch => {
            let mut l = Link::new()?;
            l.ask(&Request::Watch)?;
            loop {
                print!("{}", l.line()?);
                std::io::stdout().flush()?;
            }
        }
    }
    Ok(())
}
