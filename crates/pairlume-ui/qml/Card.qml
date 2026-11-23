// SPDX-License-Identifier: GPL-3.0-or-later
import QtQuick
import dev.pairlume

// The card the pairing window is, for everything else: a title, a line under it, one thing in the middle.
Rectangle {
    id: c
    property string title
    property string line
    property color lineColor: Theme.dim
    // room on both sides of the title
    property int side: 30
    property int head: 34
    default property alias inside: box.data
    readonly property int below: head + 72
    signal lineClicked
    property bool lineClickable: false
    radius: Math.min(32, width * 0.076)
    // there is a lot to read here: not as thin as the pairing window
    property bool solid: false
    color: Theme.fade(Theme.surface, solid ? 1 : Math.max(0.94, Theme.glass))
    border.color: Theme.fade(Theme.text, 0.12)
    // the light on the upper edge
    Rectangle {
        anchors { fill: parent; margins: 1 }
        radius: Math.max(0, c.radius - 1)
        gradient: Gradient {
            GradientStop { position: 0; color: Theme.fade(Theme.text, 0.08) }
            GradientStop { position: Math.min(1, 168 / Math.max(168, c.height)); color: Theme.fade(Theme.text, 0) }
        }
    }
    Text {
        id: t
        anchors { top: parent.top; topMargin: c.head; horizontalCenter: parent.horizontalCenter }
        width: parent.width - 2 * c.side
        horizontalAlignment: Text.AlignHCenter
        text: c.title
        textFormat: Text.PlainText
        elide: Text.ElideRight
        color: Theme.text
        font { pixelSize: 25; weight: Font.Bold }
        Behavior on text { SequentialAnimation {
            NumberAnimation { target: t; property: "opacity"; to: 0; duration: 110 }
            PropertyAction {}
            NumberAnimation { target: t; property: "opacity"; to: 1; duration: 200 }
        } }
    }
    Text {
        id: l
        anchors { top: t.bottom; topMargin: 6; horizontalCenter: parent.horizontalCenter }
        width: Math.min(implicitWidth, parent.width - 2 * c.side)
        horizontalAlignment: Text.AlignHCenter
        text: c.line
        textFormat: Text.PlainText
        elide: Text.ElideRight
        color: lm.containsMouse ? Theme.text : c.lineColor
        font.pixelSize: 14
        MouseArea { id: lm; anchors.fill: parent; enabled: c.lineClickable; hoverEnabled: enabled; cursorShape: Qt.PointingHandCursor; onClicked: c.lineClicked() }
    }
    Item { id: box; anchors.fill: parent }
}
