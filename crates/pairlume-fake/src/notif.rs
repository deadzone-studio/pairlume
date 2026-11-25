// SPDX-License-Identifier: GPL-3.0-or-later
//! Notifications that never were: a chat that can be answered, a mail, a parcel.
use pairlume_core::message::{Msg, NotifAction, NotifWhat, Notification};

pub struct Notifs {
    now: Vec<Notification>,
}

fn act(title: &str, reply: bool) -> NotifAction {
    NotifAction { title: title.into(), reply }
}

impl Notifs {
    pub fn new(now: i64) -> Self {
        let n = |key: &str,
                 app: &str,
                 app_name: &str,
                 title: &str,
                 text: &str,
                 ago: i64,
                 actions: Vec<NotifAction>,
                 icon: Option<String>| Notification {
            key: key.into(),
            app: app.into(),
            app_name: app_name.into(),
            title: title.into(),
            text: text.into(),
            when: now - ago,
            actions,
            icon,
            progress: None,
        };
        Notifs {
            now: vec![
                n(
                    "0|chat|1",
                    "org.example.chat",
                    "Chat",
                    "Emma",
                    "Are you coming tonight?",
                    120_000,
                    vec![act("Reply", true), act("Mark as read", false)],
                    Some(crate::sms::emma()),
                ),
                n(
                    "0|mail|7",
                    "org.example.mail",
                    "Mail",
                    "Shop",
                    "Your order is ready to pick up",
                    900_000,
                    vec![act("Archive", false)],
                    Some(crate::sms::mom()),
                ),
                n(
                    "0|parcel|3",
                    "org.example.parcel",
                    "Parcel",
                    "Delivery today",
                    "The courier will come between 12 and 2.",
                    3_600_000,
                    vec![],
                    None,
                ),
            ],
        }
    }

    /// all of them, as a phone sends them when it connects
    pub fn all(&self) -> Vec<Msg> {
        self.now.iter().cloned().map(Msg::Notif).collect()
    }

    /// the answer to notif_do, and what changes on the phone
    pub fn answer(&mut self, m: Msg) -> Vec<Msg> {
        let Msg::NotifDo { req, key, what, action, text } = m else { return vec![] };
        let no = |r: &str| vec![Msg::NotifError { req, reason: r.into() }];
        let Some(i) = self.now.iter().position(|n| n.key == key) else { return no("That notification is gone") };
        let button = action.and_then(|a| self.now[i].actions.get(a as usize).cloned());
        match what {
            NotifWhat::Dismiss => {
                self.now.remove(i);
                vec![Msg::NotifDone { req }, Msg::NotifGone { key }]
            }
            NotifWhat::Action => match button {
                Some(_) => {
                    self.now.remove(i);
                    vec![Msg::NotifDone { req }, Msg::NotifGone { key }]
                }
                None => no("It has no such button"),
            },
            NotifWhat::Reply => match button {
                Some(b) if b.reply => {
                    // a chat app shows the answer in the notification
                    let n = &mut self.now[i];
                    n.text = format!("You: {}", text.unwrap_or_default());
                    n.icon = None;
                    vec![Msg::NotifDone { req }, Msg::Notif(n.clone())]
                }
                _ => no("That button takes no answer"),
            },
        }
    }
}
