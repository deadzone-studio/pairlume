// SPDX-License-Identifier: GPL-3.0-or-later
import QtQuick
import dev.pairlume

Rectangle {
    id: p
    property string text
    property bool filled: false
    property bool chosen: false
    signal clicked
    implicitWidth: t.implicitWidth + 36
    implicitHeight: 42
    radius: height / 2
    opacity: enabled ? 1 : 0.45
    color: filled || chosen ? Theme.accent : Theme.fade(Theme.text, m.containsMouse ? 0.14 : 0.07)
    scale: m.pressed ? 0.95 : 1
    activeFocusOnTab: true
    border.width: activeFocus ? 2 : 0
    border.color: Theme.text
    Accessible.role: Accessible.Button
    Accessible.name: text
    Keys.onReturnPressed: clicked()
    Keys.onSpacePressed: clicked()
    Behavior on color { ColorAnimation { duration: Theme.quick } }
    Behavior on scale { NumberAnimation { duration: 240; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.spring } }
    Behavior on opacity { NumberAnimation { duration: Theme.quick } }
    Text {
        id: t
        anchors.centerIn: parent
        text: p.text
        color: p.filled || p.chosen ? Theme.ink : Theme.text
        font.pixelSize: 14
        font.weight: Font.DemiBold
    }
    MouseArea { id: m; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: p.clicked() }
}
