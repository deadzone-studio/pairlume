// SPDX-License-Identifier: GPL-3.0-or-later
import QtQuick
import QtQuick.Shapes
import dev.pairlume

// Someone's picture from the contacts; without one their letter; a bare number is an unknown person. The ring of the
// pairing phone is around those who wait for an answer.
Item {
    id: a
    property string name
    property string address
    property string photo
    property bool ring: false
    readonly property real rim: Math.max(2, Math.min(4, width * 0.06))
    readonly property string letter: {
        // the first letter there is: "8 Kuba" is a K, "★ Ola" an O
        for (const c of name) if (c.toUpperCase() !== c.toLowerCase()) return c.toUpperCase()
        return ""
    }
    width: 50
    height: width
    Accessible.ignored: true
    Rectangle {
        anchors.fill: parent
        radius: width / 2
        opacity: a.ring ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: Theme.normal } }
        gradient: Gradient {
            GradientStop { position: 0; color: Theme.accent2 }
            GradientStop { position: 1; color: Theme.accent }
        }
        Rectangle { anchors { fill: parent; margins: a.rim } radius: width / 2; color: Theme.surface }
    }
    Item {
        id: in_
        anchors { fill: parent; margins: a.rim * 2 }
        scale: a.ring ? 1 : (a.width - 2 * a.rim) / width
        Behavior on scale { NumberAnimation { duration: Theme.normal; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.spring } }
        Rectangle {
            anchors.fill: parent
            radius: width / 2
            visible: pic.status !== Image.Ready
            color: Theme.mix(Theme.surface, Theme.accent, 0.2)
            Text {
                anchors.centerIn: parent
                visible: a.letter !== ""
                text: a.letter
                textFormat: Text.PlainText
                color: Theme.text
                font { pixelSize: in_.width * 0.42; weight: Font.Bold }
            }
            // head and shoulders
            Shape {
                anchors.fill: parent
                visible: a.letter === ""
                preferredRendererType: Shape.CurveRenderer
                ShapePath {
                    strokeColor: "transparent"
                    fillColor: Theme.fade(Theme.text, 0.8)
                    scale: Qt.size(in_.width / 48, in_.width / 48)
                    PathSvg { path: "M24 10.5a7.6 7.6 0 1 1 0 15.2 7.6 7.6 0 0 1 0-15.2zM24 28.6c7.2 0 12.9 3.9 14.4 9.1A19.9 19.9 0 0 1 24 43.9a19.9 19.9 0 0 1-14.4-6.2c1.5-5.2 7.2-9.1 14.4-9.1z" }
                }
            }
        }
        // it is round already
        Image { id: pic; anchors.fill: parent; source: a.photo; sourceSize: Qt.size(128, 128); smooth: true; mipmap: true; asynchronous: true }
    }
}
