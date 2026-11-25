// SPDX-License-Identifier: GPL-3.0-or-later
import QtQuick
import dev.pairlume

// The bar of a notification that is busy (a download): how far, as it moves; or only a moving piece when the app
// cannot tell. The percent beside it in figures that do not jump.
Item {
    id: p
    property int max: 0
    property int value: 0
    property bool busy: false
    // the percent beside it; off where it already stands elsewhere
    property bool figures: true
    readonly property real part: max > 0 ? Math.min(1, value / max) : 0
    height: 18
    Rectangle {
        id: track
        anchors { left: parent.left; right: p.figures ? pct.left : parent.right; rightMargin: p.figures ? 10 : 0; verticalCenter: parent.verticalCenter }
        height: 5
        radius: 2.5
        color: Theme.fade(Theme.text, 0.1)
        clip: true
        Rectangle {
            visible: !p.busy
            height: parent.height
            radius: parent.radius
            width: parent.width * p.part
            color: Theme.accent
            Behavior on width { NumberAnimation { duration: Theme.normal; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.smooth } }
        }
        Rectangle {
            visible: p.busy
            height: parent.height
            radius: parent.radius
            width: parent.width * 0.3
            color: Theme.accent
            SequentialAnimation on x {
                running: p.busy && p.visible
                loops: Animation.Infinite
                NumberAnimation { from: -track.width * 0.3; to: track.width; duration: 1100; easing.type: Easing.InOutQuad }
            }
        }
    }
    Text {
        id: pct
        anchors { right: parent.right; verticalCenter: parent.verticalCenter }
        visible: !p.busy && p.figures
        text: Math.round(p.part * 100) + "%"
        color: Theme.dim
        font { pixelSize: 12; family: "monospace" }
    }
}
