// SPDX-License-Identifier: GPL-3.0-or-later
mod service;

use cxx_qt_lib::{QGuiApplication, QQmlApplicationEngine, QString, QUrl};

fn main() {
    let mut app = QGuiApplication::new();
    let mut engine = QQmlApplicationEngine::new();
    if let Some(mut e) = engine.as_mut() {
        // without its window this would only sit there
        e.as_mut().on_object_creation_failed(|_, _| std::process::exit(1)).release();
        let file = match std::env::args().nth(1).as_deref() {
            Some("messages") => "MessagesWindow",
            Some("panel") => "MessagesPanel",
            Some("bubbles") => "Bubbles",
            Some("calls") => "Calls",
            Some("settings") => "SettingsWindow",
            Some("setup") => "SetupWindow",
            Some("notifications") => "NotifWindow",
            _ => "Main",
        };
        e.load(&QUrl::from(&QString::from(format!("qrc:/qt/qml/dev/pairlume/qml/{file}.qml").as_str())));
    }
    let code = app.as_mut().map_or(1, |a| a.exec());
    std::process::exit(code);
}
