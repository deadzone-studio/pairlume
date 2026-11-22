// SPDX-License-Identifier: GPL-3.0-or-later
import QtQuick
import dev.pairlume

ListView {
    id: l
    required property Texts texts
    signal chosen(var thread)
    clip: true
    spacing: 4
    model: texts.threads
    boundsBehavior: Flickable.StopAtBounds
    cacheBuffer: 400
    onAtYEndChanged: if (atYEnd) texts.older()
    function when(ms) {
        const d = new Date(ms), now = new Date()
        if (d.toDateString() === now.toDateString()) return Qt.formatTime(d, "HH:mm")
        return now - d < 6 * 864e5 ? d.toLocaleDateString(Qt.locale(), "ddd") : Qt.formatDate(d, d.getFullYear() === now.getFullYear() ? "d MMM" : "d.MM.yyyy")
    }
    add: Transition { NumberAnimation { properties: "opacity,scale"; from: 0.6; to: 1; duration: Theme.normal; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.spring } }
    move: Transition { NumberAnimation { property: "y"; duration: Theme.normal; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.smooth } }
    moveDisplaced: move
    displaced: move
    delegate: Rectangle {
        id: row
        required property var model
        readonly property bool here: model.id === l.texts.open
        width: l.width
        height: 68
        radius: 20
        color: here ? Theme.fade(Theme.accent, 0.2) : Theme.fade(Theme.text, m.containsMouse ? 0.08 : 0)
        Behavior on color { ColorAnimation { duration: Theme.quick } }
        Accessible.role: Accessible.ListItem
        Accessible.name: l.texts.title(model) + ", " + model.snippet
        Avatar { id: av; x: 11; anchors.verticalCenter: parent.verticalCenter; name: l.texts.title(row.model); unread: row.model.unread }
        Text {
            id: who
            anchors { left: av.right; leftMargin: 12; right: time.left; rightMargin: 8; top: parent.top; topMargin: 13 }
            text: l.texts.title(row.model)
            textFormat: Text.PlainText
            elide: Text.ElideRight
            color: Theme.text
            font.pixelSize: 15
            font.weight: row.model.unread > 0 ? Font.Bold : Font.DemiBold
        }
        Text { id: time; anchors { right: parent.right; rightMargin: 14; baseline: who.baseline } text: l.when(row.model.date); color: Theme.dim; font.pixelSize: 11 }
        Text {
            anchors { left: who.left; right: parent.right; rightMargin: 14; top: who.bottom; topMargin: 4 }
            text: row.model.snippet.replace(/\s+/g, " ")
            textFormat: Text.PlainText
            elide: Text.ElideRight
            color: row.model.unread > 0 ? Theme.text : Theme.dim
            font.pixelSize: 13
        }
        MouseArea { id: m; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: l.chosen({ id: row.model.id, name: row.model.name, address: row.model.address }) }
    }
}
