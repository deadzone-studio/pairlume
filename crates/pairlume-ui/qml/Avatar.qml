// SPDX-License-Identifier: GPL-3.0-or-later
import QtQuick
import QtQuick.Shapes
import dev.pairlume

// Someone's picture from the contacts; without one their letter; a bare number is an unknown person.
Item {
    id: a
    property string name
    property string address
    property string photo
    property int unread: 0
    readonly property string letter: {
        // the first letter there is: "8 Kuba" is a K, "★ Ola" an O
        for (const c of name) if (c.toUpperCase() !== c.toLowerCase()) return c.toUpperCase()
        return ""
    }
    // the same person always has the same color
    readonly property real tone: { const s = address || name; let h = 7; for (let i = 0; i < s.length; i++) h = (h * 31 + s.charCodeAt(i)) % 9973; return h / 9973 }
    readonly property real hue: (Math.max(0, Theme.accent.hslHue) + (tone - 0.5) * 0.5 + 1) % 1
    width: 48
    height: 48
    Accessible.ignored: true
    Rectangle {
        anchors.fill: parent
        radius: width / 2
        visible: pic.status !== Image.Ready
        gradient: Gradient {
            GradientStop { position: 0; color: Qt.hsla(a.hue, a.letter ? 0.55 : 0.12, 0.72, 1) }
            GradientStop { position: 1; color: Qt.hsla(a.hue, a.letter ? 0.5 : 0.12, 0.52, 1) }
        }
        Text {
            anchors.centerIn: parent
            visible: a.letter !== ""
            text: a.letter
            textFormat: Text.PlainText
            color: "white"
            font.pixelSize: a.width * 0.44
            font.weight: Font.DemiBold
        }
        // head and shoulders
        Shape {
            anchors.fill: parent
            visible: a.letter === ""
            preferredRendererType: Shape.CurveRenderer
            ShapePath {
                strokeColor: "transparent"
                fillColor: Qt.rgba(1, 1, 1, 0.92)
                scale: Qt.size(a.width / 48, a.width / 48)
                PathSvg { path: "M24 10.5a7.6 7.6 0 1 1 0 15.2 7.6 7.6 0 0 1 0-15.2zM24 28.6c7.2 0 12.9 3.9 14.4 9.1A19.9 19.9 0 0 1 24 43.9a19.9 19.9 0 0 1-14.4-6.2c1.5-5.2 7.2-9.1 14.4-9.1z" }
            }
        }
    }
    // it is round already
    Image { id: pic; anchors.fill: parent; source: a.photo; sourceSize: Qt.size(128, 128); smooth: true; mipmap: true; asynchronous: true; opacity: status === Image.Ready ? 1 : 0; Behavior on opacity { NumberAnimation { duration: Theme.quick } } }
    Rectangle {
        visible: a.unread > 0
        anchors { right: parent.right; top: parent.top; margins: -3 }
        width: Math.max(19, n.implicitWidth + 10)
        height: 19
        radius: 9.5
        color: Theme.accent
        Text { id: n; anchors.centerIn: parent; text: a.unread > 99 ? "99+" : a.unread; color: Theme.ink; font.pixelSize: 11; font.weight: Font.Bold }
    }
}
