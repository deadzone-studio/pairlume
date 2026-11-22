// SPDX-License-Identifier: GPL-3.0-or-later
use cxx_qt_build::{CxxQtBuilder, QmlFile, QmlModule};

const PAGES: [&str; 16] = [
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
];

fn main() {
    let pages = PAGES.iter().map(|p| QmlFile::from(format!("qml/{p}.qml")));
    let files = pages.chain([QmlFile::from("qml/Theme.qml").singleton(true)]);
    CxxQtBuilder::new_qml_module(QmlModule::new("dev.pairlume").qml_files(files))
        .qt_module("Quick")
        .qt_module("Network")
        .files(["src/service.rs"])
        .build();
}
