// SPDX-License-Identifier: GPL-3.0-or-later
//! Three ways to make sure the device on the other end of the link is the one in your hand (docs/protocol.md).
//!
//! Shake:  both screens show six digits made from both certificates and one random number from each side. The phone
//!         commits to its number before it sees the computer's, so someone in between gets one guess in a million.
//! Qr:     the computer's fingerprint and a one-time secret come through the camera.
//! Digits: six digits from the computer's screen are proved bit by bit, like Bluetooth's passkey entry: every bit is
//!         committed to by both sides before either shows it. The digits are used for one try only.
use crate::{
    identity::{Fingerprint, from_hex, to_hex},
    message::{Msg, PairMode},
    wire::{STEP, recv_step, send},
};
use anyhow::{Context, Result, bail};
use ring::{
    digest, hmac,
    rand::{SecureRandom, SystemRandom},
};
use std::{future::Future, time::Duration};
use tokio::io::{AsyncRead, AsyncWrite};

/// how long a person may take to look at two screens
pub const HUMAN: Duration = Duration::from_secs(90);
const ROUNDS: u8 = 20; // 999999 < 2^20

pub fn random<const N: usize>() -> [u8; N] {
    let mut b = [0; N];
    SystemRandom::new().fill(&mut b).expect("the system's random numbers");
    b
}

/// six digits, every value equally likely
pub fn random_digits() -> String {
    loop {
        let n = u32::from_be_bytes(random::<4>()) >> 12; // 20 bits
        if n < 1_000_000 {
            return format!("{n:06}");
        }
    }
}

/// both ends of the link, always in this order
#[derive(Clone, Copy)]
pub struct Ends {
    pub computer: Fingerprint,
    pub phone: Fingerprint,
}

impl Ends {
    fn mix(&self, label: &str, rest: &[&[u8]]) -> Vec<u8> {
        let mut v = format!("pairlume 1 {label}\0").into_bytes();
        v.extend_from_slice(&self.computer.0);
        v.extend_from_slice(&self.phone.0);
        rest.iter().for_each(|r| v.extend_from_slice(r));
        v
    }
    fn mac(&self, key: &[u8], label: &str, rest: &[&[u8]]) -> String {
        to_hex(hmac::sign(&hmac::Key::new(hmac::HMAC_SHA256, key), &self.mix(label, rest)).as_ref())
    }
    fn check(&self, key: &[u8], label: &str, rest: &[&[u8]], mac: &str) -> Result<()> {
        let k = hmac::Key::new(hmac::HMAC_SHA256, key);
        hmac::verify(&k, &self.mix(label, rest), &from_hex(mac)?).map_err(|_| anyhow::anyhow!("the codes do not match"))
    }
    fn code(&self, nc: &[u8; 32], np: &[u8; 32]) -> String {
        let d = digest::digest(&digest::SHA256, &self.mix("code", &[nc, np]));
        let n = u64::from_be_bytes(d.as_ref()[..8].try_into().expect("8 bytes"));
        format!("{:06}", n % 1_000_000)
    }
}

fn nonce(s: &str) -> Result<[u8; 32]> {
    from_hex(s)?.try_into().ok().context("a random number of the wrong size")
}

fn unexpected<T>(m: Msg) -> Result<T> {
    bail!("unexpected message while pairing: {m:?}")
}

async fn get_nonce<S: AsyncRead + Unpin>(s: &mut S) -> Result<[u8; 32]> {
    match recv_step(s, STEP).await? {
        Msg::Nonce { nonce: n } => nonce(&n),
        m => unexpected(m),
    }
}
async fn get_commit<S: AsyncRead + Unpin>(s: &mut S) -> Result<String> {
    match recv_step(s, STEP).await? {
        Msg::Commit { mac } => Ok(mac),
        m => unexpected(m),
    }
}
async fn get_proof<S: AsyncRead + Unpin>(s: &mut S) -> Result<String> {
    match recv_step(s, STEP).await? {
        Msg::Proof { mac } => Ok(mac),
        m => unexpected(m),
    }
}

/// asks the person here, tells the other side, waits for the person there
async fn both_agree<S, F, Fut>(s: &mut S, code: String, ask: F) -> Result<()>
where
    S: AsyncRead + AsyncWrite + Unpin,
    F: FnOnce(String) -> Fut,
    Fut: Future<Output = bool>,
{
    let ok = tokio::time::timeout(HUMAN, ask(code)).await.unwrap_or(false);
    send(s, &Msg::Confirm { ok }).await?;
    if !ok {
        bail!("not confirmed here");
    }
    match recv_step(s, HUMAN + STEP).await? {
        Msg::Confirm { ok: true } => Ok(()),
        Msg::Confirm { ok: false } => bail!("not confirmed on the other device"),
        m => unexpected(m),
    }
}

pub async fn shake_phone<S, F, Fut>(s: &mut S, e: Ends, ask: F) -> Result<()>
where
    S: AsyncRead + AsyncWrite + Unpin,
    F: FnOnce(String) -> Fut,
    Fut: Future<Output = bool>,
{
    send(s, &Msg::PairStart { mode: PairMode::Shake }).await?;
    let np = random::<32>();
    send(s, &Msg::Commit { mac: e.mac(&np, "shake", &[]) }).await?;
    let nc = get_nonce(s).await?;
    send(s, &Msg::Nonce { nonce: to_hex(&np) }).await?;
    both_agree(s, e.code(&nc, &np), ask).await
}

pub async fn shake_computer<S, F, Fut>(s: &mut S, e: Ends, ask: F) -> Result<()>
where
    S: AsyncRead + AsyncWrite + Unpin,
    F: FnOnce(String) -> Fut,
    Fut: Future<Output = bool>,
{
    let c = get_commit(s).await?;
    let nc = random::<32>();
    send(s, &Msg::Nonce { nonce: to_hex(&nc) }).await?;
    let np = get_nonce(s).await?;
    e.check(&np, "shake", &[], &c)?;
    both_agree(s, e.code(&nc, &np), ask).await
}

pub async fn qr_phone<S: AsyncRead + AsyncWrite + Unpin>(s: &mut S, e: Ends, secret: &[u8]) -> Result<()> {
    send(s, &Msg::PairStart { mode: PairMode::Qr }).await?;
    send(s, &Msg::Proof { mac: e.mac(secret, "qr phone", &[]) }).await?;
    e.check(secret, "qr computer", &[], &get_proof(s).await?)
}

pub async fn qr_computer<S: AsyncRead + AsyncWrite + Unpin>(s: &mut S, e: Ends, secret: &[u8]) -> Result<()> {
    e.check(secret, "qr phone", &[], &get_proof(s).await?)?;
    send(s, &Msg::Proof { mac: e.mac(secret, "qr computer", &[]) }).await
}

fn bits(digits: &str) -> Result<u32> {
    if digits.len() != 6 || !digits.bytes().all(|b| b.is_ascii_digit()) {
        bail!("the code has six digits");
    }
    Ok(digits.parse()?)
}

pub async fn digits_phone<S: AsyncRead + AsyncWrite + Unpin>(s: &mut S, e: Ends, digits: &str) -> Result<()> {
    let n = bits(digits)?;
    send(s, &Msg::PairStart { mode: PairMode::Digits }).await?;
    for i in 0..ROUNDS {
        let part = [i, (n >> i & 1) as u8];
        let np = random::<32>();
        let theirs = get_commit(s).await?;
        send(s, &Msg::Commit { mac: e.mac(&np, "digit phone", &[&part]) }).await?;
        let nc = get_nonce(s).await?;
        e.check(&nc, "digit computer", &[&part], &theirs)?;
        send(s, &Msg::Nonce { nonce: to_hex(&np) }).await?;
    }
    match recv_step(s, STEP).await? {
        Msg::Confirm { ok: true } => Ok(()),
        m => unexpected(m),
    }
}

pub async fn digits_computer<S: AsyncRead + AsyncWrite + Unpin>(s: &mut S, e: Ends, digits: &str) -> Result<()> {
    let n = bits(digits)?;
    for i in 0..ROUNDS {
        let part = [i, (n >> i & 1) as u8];
        let nc = random::<32>();
        send(s, &Msg::Commit { mac: e.mac(&nc, "digit computer", &[&part]) }).await?;
        let theirs = get_commit(s).await?;
        send(s, &Msg::Nonce { nonce: to_hex(&nc) }).await?;
        let np = get_nonce(s).await?;
        e.check(&np, "digit phone", &[&part], &theirs)?;
    }
    send(s, &Msg::Confirm { ok: true }).await
}

/// what the QR code holds
#[derive(Clone, Debug, PartialEq)]
pub struct QrCode {
    pub fingerprint: Fingerprint,
    pub secret: [u8; 16],
    pub addr: std::net::SocketAddr,
}

impl QrCode {
    pub fn uri(&self) -> String {
        format!("pairlume://pair?v=1&a={}&f={}&s={}", self.addr, self.fingerprint, to_hex(&self.secret))
    }
    pub fn parse(s: &str) -> Result<Self> {
        let q = s.strip_prefix("pairlume://pair?").context("not a Pairlume code")?;
        let get = |k: &str| {
            q.split('&').find_map(|p| p.strip_prefix(k)?.strip_prefix('=')).with_context(|| format!("the code has no {k}"))
        };
        if get("v")? != "1" {
            bail!("the code is from another version of Pairlume");
        }
        Ok(Self {
            fingerprint: get("f")?.parse()?,
            secret: from_hex(get("s")?)?.try_into().ok().context("the code is damaged")?,
            addr: get("a")?.parse()?,
        })
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use tokio::io::{DuplexStream, duplex};

    fn ends() -> Ends {
        Ends { computer: Fingerprint([1; 32]), phone: Fingerprint([2; 32]) }
    }
    fn pipe() -> (DuplexStream, DuplexStream) {
        duplex(64 * 1024)
    }
    async fn started(s: &mut DuplexStream, want: PairMode) {
        assert_eq!(recv_step(s, STEP).await.unwrap(), Msg::PairStart { mode: want });
    }

    #[tokio::test]
    async fn shake_shows_the_same_code() {
        let (mut p, mut c) = pipe();
        let (tx, mut rx) = tokio::sync::mpsc::unbounded_channel();
        let tx2 = tx.clone();
        let phone = tokio::spawn(async move { shake_phone(&mut p, ends(), |c| async move { tx.send(c).is_ok() }).await });
        started(&mut c, PairMode::Shake).await;
        shake_computer(&mut c, ends(), |c| async move { tx2.send(c).is_ok() }).await.unwrap();
        phone.await.unwrap().unwrap();
        assert_eq!(rx.recv().await, rx.recv().await);
    }

    #[tokio::test]
    async fn either_side_can_refuse() {
        for (a, b) in [(true, false), (false, true)] {
            let (mut p, mut c) = pipe();
            let phone = tokio::spawn(async move { shake_phone(&mut p, ends(), |_| async move { a }).await });
            started(&mut c, PairMode::Shake).await;
            assert!(shake_computer(&mut c, ends(), |_| async move { b }).await.is_err());
            assert!(phone.await.unwrap().is_err());
        }
    }

    #[tokio::test]
    async fn the_phone_cannot_change_its_number_after_seeing_ours() {
        let (mut p, mut c) = pipe();
        tokio::spawn(async move {
            send(&mut p, &Msg::Commit { mac: ends().mac(&[1; 32], "shake", &[]) }).await.unwrap();
            get_nonce(&mut p).await.unwrap();
            send(&mut p, &Msg::Nonce { nonce: to_hex(&[2; 32]) }).await.unwrap();
        });
        let r = shake_computer(&mut c, ends(), |_| async { panic!("nobody may be asked") }).await;
        assert!(r.is_err());
    }

    #[tokio::test]
    async fn digits_right_and_wrong() {
        for (typed, ok) in [("012345", true), ("012344", false), ("812345", false), ("999999", false)] {
            let (mut p, mut c) = pipe();
            let phone = tokio::spawn(async move { digits_phone(&mut p, ends(), typed).await });
            started(&mut c, PairMode::Digits).await;
            let r = digits_computer(&mut c, ends(), "012345").await;
            drop(c);
            assert_eq!(r.is_ok(), ok, "{typed}");
            assert_eq!(phone.await.unwrap().is_ok(), ok, "{typed}");
        }
        let (mut p, _c) = pipe();
        assert!(digits_phone(&mut p, ends(), "12345").await.is_err());
        assert!(digits_phone(&mut p, ends(), "12345x").await.is_err());
    }

    #[tokio::test]
    async fn qr_right_and_wrong() {
        for (secret, ok) in [([9; 16], true), ([8; 16], false)] {
            let (mut p, mut c) = pipe();
            let phone = tokio::spawn(async move { qr_phone(&mut p, ends(), &secret).await });
            started(&mut c, PairMode::Qr).await;
            let r = qr_computer(&mut c, ends(), &[9; 16]).await;
            drop(c);
            assert_eq!(r.is_ok(), ok);
            assert_eq!(phone.await.unwrap().is_ok(), ok);
        }
    }

    /// the two ends do not see the same certificates: someone sits in between
    #[tokio::test]
    async fn another_certificate_in_between_breaks_every_way() {
        let mitm = |e: Ends| Ends { computer: Fingerprint([66; 32]), ..e };
        let (mut p, mut c) = pipe();
        let phone = tokio::spawn(async move { digits_phone(&mut p, mitm(ends()), "012345").await });
        started(&mut c, PairMode::Digits).await;
        assert!(digits_computer(&mut c, ends(), "012345").await.is_err());
        drop(c);
        assert!(phone.await.unwrap().is_err());

        let (mut p, mut c) = pipe();
        let phone = tokio::spawn(async move { qr_phone(&mut p, mitm(ends()), &[9; 16]).await });
        started(&mut c, PairMode::Qr).await;
        assert!(qr_computer(&mut c, ends(), &[9; 16]).await.is_err());
        drop(c);
        assert!(phone.await.unwrap().is_err());

        assert_ne!(ends().code(&[3; 32], &[4; 32]), mitm(ends()).code(&[3; 32], &[4; 32]));
    }

    #[test]
    fn qr_code_round_trip() {
        let q = QrCode { fingerprint: Fingerprint([3; 32]), secret: [5; 16], addr: "192.168.1.2:47321".parse().unwrap() };
        assert_eq!(QrCode::parse(&q.uri()).unwrap(), q);
        let q6 = QrCode { addr: "[fe80::1]:47321".parse().unwrap(), ..q };
        assert_eq!(QrCode::parse(&q6.uri()).unwrap(), q6);
        assert!(QrCode::parse("https://example.org").is_err());
        assert!(QrCode::parse("pairlume://pair?v=2&a=1.2.3.4:5&f=00&s=00").is_err());
    }

    #[test]
    fn digits_are_six() {
        (0..200).for_each(|_| assert!(bits(&random_digits()).is_ok()));
    }
}
