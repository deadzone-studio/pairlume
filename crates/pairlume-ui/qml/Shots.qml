// SPDX-License-Identifier: GPL-3.0-or-later
import QtQuick

// --shots FOLDER: a picture of `of` whenever `what` changes, for the README (works without a screen).
Item {
    id: sh
    required property Item of
    property string what
    property int wait: 1500
    readonly property int at: Qt.application.arguments.indexOf("--shots")
    onWhatChanged: if (at > 0 && what !== "") t.restart()
    Timer { id: t; interval: sh.wait; onTriggered: sh.of.grabToImage(r => r.saveToFile(Qt.application.arguments[sh.at + 1] + "/" + sh.what + ".png")) }
}
