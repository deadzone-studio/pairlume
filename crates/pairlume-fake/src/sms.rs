// SPDX-License-Identifier: GPL-3.0-or-later
//! Conversations that never were.
use pairlume_core::message::{Face, Msg, Text, Thread};

/// name, number, (from me, text)
type Talk = (&'static str, &'static str, &'static [(bool, &'static str)]);

pub struct Sms {
    threads: Vec<(Thread, Vec<Text>)>,
    next: i64,
    now: i64,
}

impl Sms {
    pub fn new(now: i64) -> Self {
        let talks: [Talk; 16] = [
            (
                "Ola",
                "+48 555 010 001",
                &[
                    (false, "Hey, what time tonight?"),
                    (true, "6 at the cinema?"),
                    (false, "Perfect"),
                    (true, "I'll get popcorn 🍿"),
                    (false, "I'll get drinks. Don't be late this time 😄"),
                ],
            ),
            (
                "Mom",
                "+48 555 010 002",
                &[(false, "Get milk on the way"), (true, "Ok, anything else?"), (false, "Bread and butter")],
            ),
            ("", "+48 555 010 003", &[(false, "Hello, the courier will come between 12 and 2.")]),
            ("8 Jake class", "+48 555 010 004", &[(true, "Playing?"), (false, "In 10 minutes"), (true, "Waiting on the server")]),
            ("", "PARCEL", &[(false, "Your parcel is waiting. Code: 481207. Track it: https://parcel.example/t/91")]),
            (
                "Zoë Müller-Wiśniewska From Work",
                "+48 555 010 006",
                &[(false, "Please send the report by Friday, signed if you can."), (true, "I'll send it tomorrow")],
            ),
            ("", "+48 555 010 007", &[(false, "Call me back")]),
            ("Dad", "+48 555 010 008", &[(true, "Home at 8"), (false, "Fine")]),
            ("Bank", "BANK", &[(false, "Code: 930114. Do not give it to anyone.")]),
            ("Igor", "+48 555 010 010", &[(false, "Do you have the physics notes?"), (true, "Yes, I'll send them tonight")]),
            ("", "+48 555 010 011", &[(false, "Your appointment: 24.11 at 9:30")]),
            ("Amy", "+48 555 010 012", &[(false, "Happy birthday!!"), (true, "Thanks ❤️")]),
            ("Coach", "+48 555 010 013", &[(false, "Practice moved to Thursday")]),
            ("Grandma", "+48 555 010 014", &[(false, "When are you coming for dinner"), (true, "On Sunday")]),
            ("Shop", "+48 555 010 015", &[(false, "Your order is ready to pick up")]),
            ("Michael", "+48 555 010 016", &[(true, "ok")]),
        ];
        let mut s = Self { threads: vec![], next: 1000, now };
        for (i, (name, address, texts)) in talks.iter().enumerate() {
            let start = now - (i as i64 * 47 + 4) * 60_000;
            let n = texts.len() as i64;
            let list: Vec<Text> = (texts.iter().enumerate())
                .map(|(k, (out, t))| Text {
                    id: (i * 100 + k) as i64,
                    out: *out,
                    text: (*t).into(),
                    date: start - (n - 1 - k as i64) * 95_000,
                    failed: false,
                })
                .collect();
            let th = Thread {
                id: i as i64 + 1,
                address: (*address).into(),
                name: (*name).into(),
                snippet: list.last().map(|t| t.text.clone()).unwrap_or_default(),
                date: start,
                unread: [1, 0, 2].get(i).copied().unwrap_or(0),
            };
            s.threads.push((th, list));
        }
        s
    }

    fn push(&mut self, thread: usize, out: bool, text: &str) -> Text {
        self.next += 1;
        self.now += 1000;
        let t = Text { id: self.next, out, text: text.into(), date: self.now, failed: false };
        let (th, list) = &mut self.threads[thread];
        th.snippet = text.into();
        th.date = self.now;
        th.unread = if out { 0 } else { th.unread + 1 };
        list.push(t.clone());
        t
    }

    /// the answer, and a text that comes a moment later
    pub fn answer(&mut self, m: Msg) -> (Option<Msg>, Option<Msg>) {
        match m {
            Msg::SmsList { req, limit, before } => {
                let mut l: Vec<Thread> =
                    self.threads.iter().map(|t| t.0.clone()).filter(|t| before.is_none_or(|b| t.date < b)).collect();
                l.sort_by_key(|t| -t.date);
                let more = l.len() > limit as usize;
                l.truncate(limit as usize);
                (Some(Msg::SmsThreads { req, threads: l, more }), None)
            }
            Msg::SmsRead { req, thread, limit, before } => match self.threads.iter().find(|t| t.0.id == thread) {
                Some((_, list)) => {
                    let l: Vec<Text> = list.iter().filter(|t| before.is_none_or(|b| t.date < b)).cloned().collect();
                    let from = l.len().saturating_sub(limit as usize);
                    (Some(Msg::SmsMessages { req, thread, messages: l[from..].to_vec(), more: from > 0 }), None)
                }
                None => (Some(Msg::SmsError { req, reason: "no such conversation".into() }), None),
            },
            Msg::SmsPhotos { req, addresses } => {
                let art: [(&str, &[u8]); 2] = [
                    ("+48 555 010 001", include_bytes!("../art/ola.png")),
                    ("+48 555 010 002", include_bytes!("../art/mama.png")),
                ];
                let faces = (art.iter().filter(|(a, _)| addresses.iter().any(|x| x == a)))
                    .map(|(a, png)| Face { address: (*a).into(), png: base64(png) })
                    .collect();
                (Some(Msg::SmsFaces { req, faces }), None)
            }
            Msg::SmsSend { req, to, text } => match self.threads.iter().position(|t| t.0.address == to) {
                Some(i) => {
                    self.push(i, true, &text);
                    let back = self.push(i, false, "👍");
                    (Some(Msg::SmsSent { req }), Some(Msg::SmsNew { thread: self.threads[i].0.clone(), message: back }))
                }
                None => (Some(Msg::SmsError { req, reason: "this pretend phone does not know that number".into() }), None),
            },
            _ => (None, None),
        }
    }
}

/// Ola's picture, for her call
pub fn ola() -> String {
    base64(include_bytes!("../art/ola.png"))
}

fn base64(b: &[u8]) -> String {
    const ABC: &[u8; 64] = b"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
    let mut s = String::with_capacity(b.len().div_ceil(3) * 4);
    for c in b.chunks(3) {
        let n = u32::from(c[0]) << 16 | u32::from(*c.get(1).unwrap_or(&0)) << 8 | u32::from(*c.get(2).unwrap_or(&0));
        for i in 0..4 {
            s.push(if i <= c.len() { ABC[(n >> (18 - 6 * i) & 63) as usize] as char } else { '=' });
        }
    }
    s
}
