// SPDX-License-Identifier: GPL-3.0-or-later
import QtQuick
import dev.pairlume

// A little phone. `waving`: it shows what to do.
Item {
    id: ph
    property bool waving: false
    property real glow: 0
    width: 64
    height: 124
    Rectangle {
        id: body
        anchors.fill: parent
        radius: 16
        gradient: Gradient {
            GradientStop { position: 0; color: Theme.accent2 }
            GradientStop { position: 1; color: Theme.accent }
        }
        Rectangle {
            anchors { fill: parent; margins: 4 }
            radius: 12
            color: Qt.tint(Theme.surface, Theme.fade(Theme.accent, 0.12 + ph.glow * 0.6))
            Rectangle { anchors { top: parent.top; topMargin: 8; horizontalCenter: parent.horizontalCenter } width: 18; height: 5; radius: 2.5; color: Theme.fade(Theme.text, 0.35) }
            Rectangle { anchors { bottom: parent.bottom; bottomMargin: 7; horizontalCenter: parent.horizontalCenter } width: 22; height: 3; radius: 1.5; color: Theme.fade(Theme.text, 0.35) }
        }
        transformOrigin: Item.Bottom
        SequentialAnimation on rotation {
            running: ph.waving && ph.visible
            loops: Animation.Infinite
            alwaysRunToEnd: true
            PauseAnimation { duration: 900 }
            NumberAnimation { to: -13; duration: 90; easing.type: Easing.OutQuad }
            NumberAnimation { to: 12; duration: 120; easing.type: Easing.InOutQuad }
            NumberAnimation { to: -9; duration: 110; easing.type: Easing.InOutQuad }
            NumberAnimation { to: 6; duration: 100; easing.type: Easing.InOutQuad }
            NumberAnimation { to: 0; duration: 420; easing.type: Easing.OutElastic }
        }
    }
}
