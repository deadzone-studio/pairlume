// SPDX-License-Identifier: GPL-3.0-or-later
import QtQuick
import dev.pairlume

Rectangle {
    id: a
    property string name
    property int unread: 0
    // the same person always has the same color
    readonly property real tone: { let h = 0; for (let i = 0; i < name.length; i++) h = (h * 31 + name.charCodeAt(i)) % 997; return h / 997 }
    width: 46
    height: 46
    radius: width / 2
    gradient: Gradient {
        GradientStop { position: 0; color: Qt.hsla((Theme.accent.hslHue + a.tone * 0.35) % 1, 0.62, 0.66, 1) }
        GradientStop { position: 1; color: Qt.hsla((Theme.accent.hslHue + a.tone * 0.35 + 0.07) % 1, 0.6, 0.5, 1) }
    }
    Text {
        anchors.centerIn: parent
        // a number has no initial
        readonly property string one: a.name.charAt(0)
        text: one.toUpperCase() !== one.toLowerCase() ? one.toUpperCase() : "#"
        textFormat: Text.PlainText
        color: "#0b1020"
        font.pixelSize: a.width * 0.42
        font.weight: Font.Bold
    }
    Rectangle {
        visible: a.unread > 0
        anchors { right: parent.right; top: parent.top; margins: -3 }
        width: Math.max(19, n.implicitWidth + 10)
        height: 19
        radius: 9.5
        color: Theme.accent2
        border { width: 2; color: Theme.surface }
        Text { id: n; anchors.centerIn: parent; text: a.unread > 99 ? "99+" : a.unread; color: Theme.ink; font.pixelSize: 10; font.weight: Font.Bold }
    }
}
