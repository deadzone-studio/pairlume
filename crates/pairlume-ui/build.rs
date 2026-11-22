// SPDX-License-Identifier: GPL-3.0-or-later
use cxx_qt_build::{CxxQtBuilder, QmlFile, QmlModule};

fn main() {
    let pages =
        ["qml/Main.qml", "qml/PairingCard.qml", "qml/Phone.qml", "qml/Rings.qml", "qml/Digits.qml", "qml/Qr.qml", "qml/Pill.qml"];
    let files = pages.map(QmlFile::from).into_iter().chain([QmlFile::from("qml/Theme.qml").singleton(true)]);
    CxxQtBuilder::new_qml_module(QmlModule::new("dev.pairlume").qml_files(files))
        .qt_module("Quick")
        .qt_module("Network")
        .files(["src/service.rs"])
        .build();
}
