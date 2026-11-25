// SPDX-License-Identifier: GPL-3.0-or-later
use cxx_qt_build::{CxxQtBuilder, QmlFile, QmlModule};

const PAGES: [&str; 31] = [
    "Main",
    "PairingCard",
    "Phone",
    "Rings",
    "Digits",
    "Qr",
    "Pill",
    "Texts",
    "Avatar",
    "ThreadList",
    "Talk",
    "MessagesView",
    "MessagesWindow",
    "MessagesPanel",
    "Bubbles",
    "Shots",
    "Card",
    "ListCard",
    "TalkCard",
    "Moment",
    "Composer",
    "CallCard",
    "Calls",
    "Mover",
    "BtCard",
    "SettingsWindow",
    "SetupWindow",
    "NotifCard",
    "NotifBanner",
    "ProgressLine",
    "NotifWindow",
];

fn main() {
    let pages = PAGES.iter().map(|p| QmlFile::from(format!("qml/{p}.qml")));
    let files = pages.chain(["qml/Theme.qml", "qml/Tr.qml"].map(|p| QmlFile::from(p).singleton(true)));
    CxxQtBuilder::new_qml_module(QmlModule::new("dev.pairlume").qml_files(files))
        .qt_module("Quick")
        .qt_module("Network")
        .files(["src/service.rs"])
        .build();
}
