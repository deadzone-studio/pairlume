// SPDX-License-Identifier: GPL-3.0-or-later
//! Conversations that never were.
use pairlume_core::message::{Msg, Text, Thread};

/// name, number, (from me, text)
type Talk = (&'static str, &'static str, &'static [(bool, &'static str)]);

pub struct Sms {
    threads: Vec<(Thread, Vec<Text>)>,
    next: i64,
    now: i64,
}

impl Sms {
    pub fn new(now: i64) -> Self {
        let talks: [Talk; 5] = [
            (
                "Ola",
                "+48 555 010 001",
                &[
                    (false, "Hej, o której dzisiaj?"),
                    (true, "18 pod kinem?"),
                    (false, "Idealnie"),
                    (true, "Biorę popcorn 🍿"),
                    (false, "A ja picie. Nie spóźnij się tym razem 😄"),
                ],
            ),
            ("Mama", "+48 555 010 002", &[(false, "Kup mleko po drodze"), (true, "Ok, coś jeszcze?"), (false, "Chleb i masło")]),
            ("", "+48 555 010 003", &[(false, "Dzień dobry, kurier będzie między 12 a 14.")]),
            ("Kuba", "+48 555 010 004", &[(true, "Gramy?"), (false, "Za 10 minut"), (true, "Czekam na serwerze")]),
            ("", "PARCEL", &[(false, "Your parcel is waiting. Code: 000000.")]),
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
                unread: u32::from(i == 0),
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
