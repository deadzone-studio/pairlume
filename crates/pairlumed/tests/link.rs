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

// ---------- texts ----------
fn thread(snippet: &str) -> pairlume_core::message::Thread {
    pairlume_core::message::Thread {
        id: 1,
        address: "+48 555 010 001".into(),
        name: "Emma".into(),
        snippet: snippet.into(),
        date: 1,
        unread: 0,
    }
}

/// answers one question of the computer with `f`
async fn answer(l: &mut client::Link, f: impl Fn(u64) -> Msg) -> Msg {
    loop {
        let m = next(l).await.unwrap();
        let req = match &m {
            Msg::SmsList { req, .. } | Msg::SmsRead { req, .. } | Msg::SmsSend { req, .. } => *req,
            _ => continue,
        };
        send(&mut l.stream, &f(req)).await.unwrap();
        return m;
    }
}

#[tokio::test]
async fn texts_need_the_permission_both_ways() {
    let mut pc = Pc::new().await;
    let id = Identity::generate().unwrap();
    let mut l = pc.paired(&id).await;
    let fp = id.fingerprint;
    let e = pc.d.ask(&fp, Capability::Sms, |req| Msg::SmsList { req, limit: 1, before: None }).await.unwrap_err();
    assert!(e.to_string().contains("may not use sms"), "{e}");
    let new = Msg::SmsNew {
        thread: thread("x"),
        message: pairlume_core::message::Text { id: 1, out: false, text: "x".into(), date: 1, failed: false },
    };
    send(&mut l.stream, &new).await.unwrap();
    loop {
        if let Msg::Denied { cap } = next(&mut l).await.unwrap() {
            assert_eq!(cap, Capability::Sms);
            break;
        }
    }
    pc.d.allow(&fp, Capability::Sms, true).unwrap();
    send(&mut l.stream, &new).await.unwrap();
    pc.wait(|e| matches!(e, Event::Sms { .. }).then_some(())).await;
}

#[tokio::test]
async fn texts_are_asked_answered_and_cleaned() {
    let mut pc = Pc::new().await;
    let id = Identity::generate().unwrap();
    let mut l = pc.paired(&id).await;
    let fp = id.fingerprint;
    pc.d.allow(&fp, Capability::Sms, true).unwrap();
    let d = pc.d.clone();
    let q = tokio::spawn(async move { d.ask(&fp, Capability::Sms, |req| Msg::SmsList { req, limit: 40, before: None }).await });
    answer(&mut l, |req| Msg::SmsThreads { req, threads: vec![thread("a\u{202e}b\x1b[2J\nc")], more: false }).await;
    match q.await.unwrap().unwrap() {
        Msg::SmsThreads { threads, .. } => assert_eq!(threads[0].snippet, "ab[2J\nc"),
        m => panic!("{m:?}"),
    }
    let d = pc.d.clone();
    let q =
        tokio::spawn(
            async move { d.ask(&fp, Capability::Sms, |req| Msg::SmsSend { req, to: "1".into(), text: "hi".into() }).await },
        );
    let asked = answer(&mut l, |req| Msg::SmsError { req, reason: "no signal".into() }).await;
    assert!(matches!(asked, Msg::SmsSend { text, .. } if text == "hi"));
    assert_eq!(q.await.unwrap().unwrap_err().to_string(), "no signal");
    // an answer to nothing does no harm
    send(&mut l.stream, &Msg::SmsSent { req: 999 }).await.unwrap();
    send(&mut l.stream, &Msg::Ping).await.unwrap();
    while next(&mut l).await.unwrap() != Msg::Pong {}
}

#[tokio::test]
async fn a_question_ends_when_the_phone_goes_away() {
    let mut pc = Pc::new().await;
    let id = Identity::generate().unwrap();
    let l = pc.paired(&id).await;
    let fp = id.fingerprint;
    pc.d.allow(&fp, Capability::Sms, true).unwrap();
    let d = pc.d.clone();
    let q = tokio::spawn(async move { d.ask(&fp, Capability::Sms, |req| Msg::SmsList { req, limit: 1, before: None }).await });
    tokio::time::sleep(Duration::from_millis(100)).await;
    drop(l);
    let e = timeout(SOON, q).await.expect("it must not wait for the whole time").unwrap().unwrap_err();
    assert!(e.to_string().contains("went away"), "{e}");
    assert!(pc.d.ask(&fp, Capability::Sms, |req| Msg::SmsList { req, limit: 1, before: None }).await.is_err());
}

#[tokio::test]
async fn pictures_that_are_not_pictures_are_dropped() {
    use pairlume_core::message::Face;
    let mut pc = Pc::new().await;
    let id = Identity::generate().unwrap();
    let mut l = pc.paired(&id).await;
    let fp = id.fingerprint;
    pc.d.allow(&fp, Capability::Sms, true).unwrap();
    let d = pc.d.clone();
    let q =
        tokio::spawn(async move { d.ask(&fp, Capability::Sms, |req| Msg::SmsPhotos { req, addresses: vec!["1".into()] }).await });
    let face = |png: &str| Face { address: "1".into(), png: png.into() };
    loop {
        if let Msg::SmsPhotos { req, .. } = next(&mut l).await.unwrap() {
            let big = format!("iVBORw0KGgo{}", "A".repeat(50_000));
            let faces = vec![face("iVBORw0KGgoAAA="), face("PHN2Zz4="), face("iVBORw0KGgo\" onload"), face(&big)];
            send(&mut l.stream, &Msg::SmsFaces { req, faces }).await.unwrap();
            break;
        }
    }
    match q.await.unwrap().unwrap() {
        Msg::SmsFaces { faces, .. } => assert_eq!(faces, [face("iVBORw0KGgoAAA=")]),
        m => panic!("{m:?}"),
    }
}

// ---------- calls ----------
#[tokio::test]
async fn calls_need_the_permission_and_are_cleaned() {
    use pairlume_core::message::{CallAction, CallState};
    let mut pc = Pc::new().await;
    let id = Identity::generate().unwrap();
    let mut l = pc.paired(&id).await;
    let fp = id.fingerprint;
    let ring = |name: &str| Msg::Call {
        state: CallState::Ringing,
        number: "+48 555 010 001".into(),
        name: name.into(),
        missed: false,
        png: Some("PHN2Zz4=".into()),
    };
    send(&mut l.stream, &ring("Emma")).await.unwrap();
    loop {
        if let Msg::Denied { cap } = next(&mut l).await.unwrap() {
            assert_eq!(cap, Capability::Calls);
            break;
        }
    }
    pc.d.allow(&fp, Capability::Calls, true).unwrap();
    send(&mut l.stream, &ring("Emma\u{202e}\x1b[2J")).await.unwrap();
    let (name, png) = pc
        .wait(|e| match e {
            Event::Call { name, png, state: CallState::Ringing, .. } => Some((name.clone(), png.clone())),
            _ => None,
        })
        .await;
    assert_eq!(name, "Emma[2J");
    let now = pc.d.status()[0].call.clone().expect("the call is in the status");
    assert_eq!(now.state, CallState::Ringing);
    assert_eq!(png, None, "not a picture");
    let d = pc.d.clone();
    let q = tokio::spawn(async move {
        d.ask(&fp, Capability::Calls, |req| Msg::CallDo { req, what: CallAction::Answer, number: None }).await
    });
    loop {
        if let Msg::CallDo { req, what, .. } = next(&mut l).await.unwrap() {
            assert_eq!(what, CallAction::Answer);
            send(&mut l.stream, &Msg::CallError { req, reason: "Nothing rings".into() }).await.unwrap();
            break;
        }
    }
    assert_eq!(q.await.unwrap().unwrap_err().to_string(), "Nothing rings");
}

#[test]
fn only_phone_numbers_are_dialed() {
    use pairlumed::control::dialable;
    for ok in ["+48 555 010 001", "112", "(555) 010-0001"] {
        assert!(dialable(ok).is_ok(), "{ok}");
    }
    for no in ["", "12", "*#06#", "555+1", "1234567890123456", "tel:555010001", "555;1"] {
        assert!(dialable(no).is_err(), "{no}");
    }
}
