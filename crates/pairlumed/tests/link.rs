// SPDX-License-Identifier: GPL-3.0-or-later
//! A real service and pretend phones, over real TLS on this computer.
use pairlume_core::{
    client,
    identity::Identity,
    message::{Capability, Msg},
    pairing::QrCode,
    wire::{recv, send},
};
use pairlumed::{Daemon, Event, server};
use std::{net::SocketAddr, sync::Arc, time::Duration};
use tokio::{net::TcpListener, sync::broadcast::Receiver, time::timeout};

const SOON: Duration = Duration::from_secs(5);

struct Pc {
    d: Arc<Daemon>,
    addr: SocketAddr,
    ev: Receiver<Event>,
    dir: tempfile::TempDir,
}

impl Pc {
    async fn new() -> Self {
        let dir = tempfile::tempdir().unwrap();
        let d = Daemon::open(dir.path(), "Desk").unwrap();
        let l = TcpListener::bind("127.0.0.1:0").await.unwrap();
        let addr = l.local_addr().unwrap();
        d.set_addr(Some(addr));
        tokio::spawn(server::serve(d.clone(), l));
        Self { ev: d.events(), d, addr, dir }
    }
    fn open(&self) -> (String, QrCode) {
        match self.d.open_pairing(Duration::from_secs(30)) {
            Event::PairingOpen { digits, qr, .. } => (digits, QrCode::parse(&qr.unwrap()).unwrap()),
            e => panic!("{e:?}"),
        }
    }
    async fn wait<T>(&mut self, f: impl Fn(&Event) -> Option<T>) -> T {
        timeout(SOON, async {
            loop {
                if let Some(x) = f(&self.ev.recv().await.unwrap()) {
                    return x;
                }
            }
        })
        .await
        .expect("the event never came")
    }
    /// paired with digits, the connection is open
    async fn paired(&mut self, id: &Identity) -> client::Link {
        let (digits, _) = self.open();
        let l = client::pair_digits(id, "Phone", self.addr, &digits).await.unwrap();
        self.wait(|e| matches!(e, Event::Online { .. }).then_some(())).await;
        l
    }
}

async fn next(l: &mut client::Link) -> anyhow::Result<Msg> {
    timeout(SOON, recv(&mut l.stream)).await.expect("nothing came")
}

#[tokio::test]
async fn shake_then_reconnect_then_battery() {
    let mut pc = Pc::new().await;
    let id = Identity::generate().unwrap();
    pc.open();
    let (d, addr, phone) = (pc.d.clone(), pc.addr, id.clone());
    let (tx, rx) = tokio::sync::oneshot::channel();
    let pairing =
        tokio::spawn(
            async move { client::pair_shake(&phone, "My\x1b phone", addr, |c| async move { tx.send(c).is_ok() }).await },
        );
    let (name, code) =
        pc.wait(|e| if let Event::PairingCode { name, code } = e { Some((name.clone(), code.clone())) } else { None }).await;
    assert_eq!(name, "My phone");
    assert_eq!(rx.await.unwrap(), code);
    d.answer(true).unwrap();
    drop(pairing.await.unwrap().unwrap());
    pc.wait(|e| matches!(e, Event::Offline { .. }).then_some(())).await;
    assert!(!d.pairing_open());

    // later, without any pairing
    let mut l = client::connect(&id, "My phone", addr, Some(d.identity.fingerprint)).await.unwrap();
    assert!(matches!(next(&mut l).await.unwrap(), Msg::Allowed { caps } if caps.is_empty()));
    let battery = Msg::Battery { percent: 200, charging: true };
    send(&mut l.stream, &battery).await.unwrap();
    assert_eq!(next(&mut l).await.unwrap(), Msg::Denied { cap: Capability::Battery });
    assert_eq!(d.status()[0].battery, None);

    d.allow(&id.fingerprint, Capability::Battery, true).unwrap();
    assert!(matches!(next(&mut l).await.unwrap(), Msg::Allowed { caps } if caps.contains(&Capability::Battery)));
    send(&mut l.stream, &battery).await.unwrap();
    assert_eq!(pc.wait(|e| if let Event::Battery { percent, .. } = e { Some(*percent) } else { None }).await, 100);
    send(&mut l.stream, &Msg::Ping).await.unwrap();
    assert_eq!(next(&mut l).await.unwrap(), Msg::Pong);
    d.allow(&id.fingerprint, Capability::Battery, false).unwrap();
    assert_eq!(d.status()[0].battery, None);
}

#[tokio::test]
async fn no_at_the_computer_means_no() {
    let mut pc = Pc::new().await;
    let id = Identity::generate().unwrap();
    pc.open();
    let (addr, phone) = (pc.addr, id.clone());
    let pairing = tokio::spawn(async move { client::pair_shake(&phone, "Phone", addr, |_| async { true }).await });
    pc.wait(|e| matches!(e, Event::PairingCode { .. }).then_some(())).await;
    pc.d.answer(false).unwrap();
    assert!(pairing.await.unwrap().is_err());
    assert!(pc.d.status().is_empty());
    pc.wait(|e| matches!(e, Event::PairingClosed { .. }).then_some(())).await;
    assert!(pc.d.answer(true).is_err());
}

#[tokio::test]
async fn strangers_stay_out_when_not_pairing() {
    let pc = Pc::new().await;
    let id = Identity::generate().unwrap();
    assert!(client::pair_digits(&id, "Phone", pc.addr, "000000").await.is_err());
    assert!(client::pair_shake(&id, "Phone", pc.addr, |_| async { true }).await.is_err());
    assert!(pc.d.status().is_empty());
}

#[tokio::test]
async fn wrong_digits_close_the_window() {
    let mut pc = Pc::new().await;
    let id = Identity::generate().unwrap();
    let (digits, _) = pc.open();
    let wrong = format!("{:06}", (digits.parse::<u32>().unwrap() + 1) % 1_000_000);
    assert!(client::pair_digits(&id, "Phone", pc.addr, &wrong).await.is_err());
    pc.wait(|e| matches!(e, Event::PairingClosed { .. }).then_some(())).await;
    assert!(client::pair_digits(&id, "Phone", pc.addr, &digits).await.is_err());
    assert!(pc.d.status().is_empty());
}

#[tokio::test]
async fn qr_right_wrong_and_another_computer() {
    let mut pc = Pc::new().await;
    let id = Identity::generate().unwrap();
    let (_, qr) = pc.open();
    let other = QrCode { fingerprint: id.fingerprint, ..qr.clone() };
    assert!(client::pair_qr(&id, "Phone", &other).await.is_err());
    let wrong = QrCode { secret: [0; 16], ..qr.clone() };
    assert!(client::pair_qr(&id, "Phone", &wrong).await.is_err());
    pc.wait(|e| matches!(e, Event::PairingClosed { .. }).then_some(())).await;
    let (_, new) = pc.open();
    assert!(client::pair_qr(&id, "Phone", &QrCode { secret: qr.secret, ..new }).await.is_err(), "an old secret");
    let (_, qr) = pc.open();
    client::pair_qr(&id, "Phone", &qr).await.unwrap();
    assert_eq!(pc.wait(|e| if let Event::Paired { name, .. } = e { Some(name.clone()) } else { None }).await, "Phone");
}

#[tokio::test]
async fn one_phone_at_a_time() {
    let mut pc = Pc::new().await;
    let (a, b) = (Identity::generate().unwrap(), Identity::generate().unwrap());
    let (digits, _) = pc.open();
    let addr = pc.addr;
    let first = tokio::spawn(async move { client::pair_shake(&a, "First", addr, |_| async { true }).await });
    pc.wait(|e| matches!(e, Event::PairingCode { .. }).then_some(())).await;
    assert!(client::pair_digits(&b, "Second", pc.addr, &digits).await.is_err());
    pc.d.answer(true).unwrap();
    first.await.unwrap().unwrap();
    assert_eq!(pc.d.status().len(), 1);
}

#[tokio::test]
async fn unpairing_ends_the_connection_and_keeps_it_out() {
    let mut pc = Pc::new().await;
    let id = Identity::generate().unwrap();
    let mut l = pc.paired(&id).await;
    pc.d.unpair(&id.fingerprint).unwrap();
    let gone = timeout(SOON, async { while next(&mut l).await.is_ok() {} }).await;
    assert!(gone.is_ok());
    assert!(client::connect(&id, "Phone", pc.addr, None).await.is_err());
    assert!(pc.d.unpair(&id.fingerprint).is_err());
}

#[tokio::test]
async fn the_same_phone_again_replaces_the_old_connection() {
    let mut pc = Pc::new().await;
    let id = Identity::generate().unwrap();
    let mut old = pc.paired(&id).await;
    let _new = client::connect(&id, "Phone", pc.addr, None).await.unwrap();
    pc.wait(|e| matches!(e, Event::Online { .. }).then_some(())).await;
    assert!(timeout(SOON, async { while next(&mut old).await.is_ok() {} }).await.is_ok());
    tokio::time::sleep(Duration::from_millis(100)).await;
    assert!(pc.d.status()[0].online, "the end of the old one must not count for the new one");
}

#[tokio::test]
async fn a_paired_phone_cannot_start_pairing_talk() {
    let mut pc = Pc::new().await;
    let id = Identity::generate().unwrap();
    let mut l = pc.paired(&id).await;
    send(&mut l.stream, &Msg::Confirm { ok: true }).await.unwrap();
    pc.wait(|e| matches!(e, Event::Offline { .. }).then_some(())).await;
}

#[tokio::test]
async fn pairing_survives_a_restart() {
    let mut pc = Pc::new().await;
    let id = Identity::generate().unwrap();
    drop(pc.paired(&id).await);
    let again = Daemon::open(pc.dir.path(), "Desk").unwrap();
    assert_eq!(again.identity.fingerprint, pc.d.identity.fingerprint);
    assert_eq!(again.find("Phone").unwrap(), id.fingerprint);
}

/// plain bytes, half a handshake, silence: none of it may stop the service
#[tokio::test]
async fn noise_does_no_harm() {
    use tokio::io::AsyncWriteExt;
    let mut pc = Pc::new().await;
    for junk in [&b""[..], b"GET / HTTP/1.1\r\n\r\n", &[0x16, 3, 1, 0xff, 0xff], &[0; 4096]] {
        let mut s = tokio::net::TcpStream::connect(pc.addr).await.unwrap();
        s.write_all(junk).await.unwrap();
    }
    let id = Identity::generate().unwrap();
    pc.paired(&id).await;
}

#[tokio::test]
async fn control_socket_is_private_and_answers() {
    use std::os::unix::fs::PermissionsExt;
    use tokio::io::{AsyncBufReadExt, AsyncWriteExt, BufReader};
    let pc = Pc::new().await;
    let path = pc.dir.path().join("c.sock");
    let l = pairlumed::control::listen(&path).unwrap();
    assert_eq!(std::fs::metadata(&path).unwrap().permissions().mode() & 0o777, 0o600);
    tokio::spawn(pairlumed::control::serve(pc.d.clone(), l));
    let mut s = BufReader::new(tokio::net::UnixStream::connect(&path).await.unwrap());
    for (ask, want) in [
        ("{\"cmd\":\"status\"}\n", "\"devices\":[]"),
        ("nonsense\n", "\"error\""),
        ("{\"cmd\":\"unpair\",\"device\":\"x\"}\n", "no paired device"),
        ("{\"cmd\":\"pair\"}\n", "pairing_open"),
    ] {
        s.get_mut().write_all(ask.as_bytes()).await.unwrap();
        let mut line = String::new();
        s.read_line(&mut line).await.unwrap();
        assert!(line.contains(want), "{ask} -> {line}");
    }
}
