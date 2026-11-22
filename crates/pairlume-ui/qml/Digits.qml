// SPDX-License-Identifier: GPL-3.0-or-later
import QtQuick
import dev.pairlume

// Six digits that come in one after another.
Row {
    id: d
    property string code
    spacing: 8
    Accessible.role: Accessible.StaticText
    Accessible.name: code.split("").join(" ")
    Repeater {
        model: d.code.length
        Item {
            id: cell
            required property int index
            width: 44 + (index === 2 ? 14 : 0)
            height: 60
            Rectangle {
                id: box
                width: 44
                height: 60
                radius: 14
                color: Theme.fade(Theme.accent, 0.16)
                border.color: Theme.fade(Theme.accent, 0.4)
                opacity: 0
                scale: 0.4
                Text { anchors.centerIn: parent; text: d.code[cell.index] ?? ""; color: Theme.text; font.pixelSize: 30; font.weight: Font.Bold }
                SequentialAnimation {
                    running: true
                    PauseAnimation { duration: cell.index * 70 }
                    ParallelAnimation {
                        NumberAnimation { target: box; property: "opacity"; to: 1; duration: 160 }
                        NumberAnimation { target: box; property: "scale"; to: 1; duration: 460; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.spring }
                    }
                }
            }
        }
    }
}
