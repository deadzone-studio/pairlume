// SPDX-License-Identifier: GPL-3.0-or-later
import QtQuick
import dev.pairlume

// Six digits that come in one after another.
Row {
    id: d
    property string code
    property real cell: 44
    // six and eight are read in halves
    readonly property int half: code.length === 6 || code.length === 8 ? code.length / 2 - 1 : -1
    spacing: 8
    Accessible.role: Accessible.StaticText
    Accessible.name: code.split("").join(" ")
    Repeater {
        model: d.code.length
        Item {
            id: one
            required property int index
            width: d.cell + (index === d.half ? 14 : 0)
            height: d.cell * 1.36
            Rectangle {
                id: box
                width: d.cell
                height: d.cell * 1.36
                radius: 14
                color: Theme.fade(Theme.accent, 0.16)
                border.color: Theme.fade(Theme.accent, 0.4)
                opacity: 0
                scale: 0.4
                Text { anchors.centerIn: parent; text: d.code[one.index] ?? ""; color: Theme.text; font.pixelSize: d.cell * 0.68; font.weight: Font.Bold }
                SequentialAnimation {
                    running: true
                    PauseAnimation { duration: one.index * 70 }
                    ParallelAnimation {
                        NumberAnimation { target: box; property: "opacity"; to: 1; duration: 160 }
                        NumberAnimation { target: box; property: "scale"; to: 1; duration: 460; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.spring }
                    }
                }
            }
        }
    }
}
