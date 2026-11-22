// SPDX-License-Identifier: GPL-3.0-or-later
import QtQuick
import dev.pairlume

// Rings of light that go out while the computer is looking for a phone.
Item {
    id: r
    property bool on: true
    Repeater {
        model: 4
        Rectangle {
            id: ring
            required property int index
            property real t: 0
            anchors.centerIn: parent
            width: 90 + t * (r.width - 90)
            height: width
            radius: width / 2
            color: "transparent"
            border.width: 2
            border.color: Theme.fade(index % 2 ? Theme.accent2 : Theme.accent, (1 - t) * 0.6)
            opacity: r.on ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: Theme.normal } }
            SequentialAnimation on t {
                running: r.visible
                PauseAnimation { duration: ring.index * 700 }
                NumberAnimation { from: 0; to: 1; duration: 2800; loops: Animation.Infinite; easing.type: Easing.OutQuad }
            }
        }
    }
}
