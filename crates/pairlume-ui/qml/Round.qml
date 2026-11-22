// SPDX-License-Identifier: GPL-3.0-or-later
import QtQuick
import QtQuick.Shapes
import dev.pairlume

// A round button with a drawn sign (24 x 24).
Item {
    id: r
    property string path
    property bool filled: false
    property string label
    signal clicked
    width: 40
    height: 40
    opacity: enabled ? 1 : 0.4
    activeFocusOnTab: true
    Accessible.role: Accessible.Button
    Accessible.name: label
    Keys.onReturnPressed: clicked()
    Keys.onSpacePressed: clicked()
    scale: m.pressed ? 0.88 : m.containsMouse ? 1.05 : 1
    Behavior on scale { NumberAnimation { duration: 260; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.spring } }
    Behavior on opacity { NumberAnimation { duration: Theme.quick } }
    Glass { anchors.fill: parent; radius: width / 2; visible: !r.filled }
    Rectangle {
        anchors.fill: parent
        radius: width / 2
        visible: r.filled
        gradient: Gradient {
            GradientStop { position: 0; color: Theme.accent }
            GradientStop { position: 1; color: Theme.mix(Theme.accent, Theme.accent2, 0.45) }
        }
    }
    Rectangle { anchors.fill: parent; radius: width / 2; color: "transparent"; border { width: r.activeFocus ? 2 : 0; color: Theme.text } }
    Shape {
        anchors.centerIn: parent
        width: 24
        height: 24
        preferredRendererType: Shape.CurveRenderer
        ShapePath { strokeWidth: 2.2; strokeColor: r.filled ? Theme.ink : Theme.text; fillColor: "transparent"; capStyle: ShapePath.RoundCap; joinStyle: ShapePath.RoundJoin; PathSvg { path: r.path } }
    }
    MouseArea { id: m; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: r.clicked() }
}
