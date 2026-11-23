// SPDX-License-Identifier: GPL-3.0-or-later
//! A call that never was: it rings, it can be answered, ended, or made.
use pairlume_core::message::{CallAction, CallState, Msg};

#[derive(Default)]
pub struct Calls {
    now: Option<(CallState, String, String)>,
}

impl Calls {
    pub fn ring(&mut self, number: &str, name: &str, png: Option<String>) -> Msg {
        self.now = Some((CallState::Ringing, number.into(), name.into()));
        Msg::Call { state: CallState::Ringing, number: number.into(), name: name.into(), missed: false, png }
    }

    fn state(&mut self, state: CallState, missed: bool) -> Msg {
        let (_, number, name) = self.now.take().unwrap_or((CallState::Ended, String::new(), String::new()));
        if state != CallState::Ended {
            self.now = Some((state, number.clone(), name.clone()));
        }
        Msg::Call { state, number, name, missed, png: None }
    }

    /// nobody answered in time
    pub fn missed(&mut self) -> Option<Msg> {
        matches!(self.now, Some((CallState::Ringing, ..))).then(|| self.state(CallState::Ended, true))
    }

    /// the answer, and what the call does then
    pub fn answer(&mut self, m: Msg) -> Vec<Msg> {
        let Msg::CallDo { req, what, number } = m else { return vec![] };
        let no = |reason: &str| vec![Msg::CallError { req, reason: reason.into() }];
        let ringing = matches!(self.now, Some((CallState::Ringing, ..)));
        match what {
            CallAction::Answer if ringing => vec![Msg::CallDone { req }, self.state(CallState::Talking, false)],
            CallAction::Answer => no("Nothing rings"),
            CallAction::End if self.now.is_some() => vec![Msg::CallDone { req }, self.state(CallState::Ended, false)],
            CallAction::End => no("There is no call"),
            CallAction::Dial if self.now.is_some() => no("There is a call already"),
            CallAction::Dial => {
                self.now = Some((CallState::Dialing, number.clone().unwrap_or_default(), String::new()));
                vec![
                    Msg::CallDone { req },
                    Msg::Call {
                        state: CallState::Dialing,
                        number: number.unwrap_or_default(),
                        name: String::new(),
                        missed: false,
                        png: None,
                    },
                ]
            }
        }
    }
}
