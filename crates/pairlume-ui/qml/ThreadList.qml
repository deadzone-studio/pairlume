// SPDX-License-Identifier: GPL-3.0-or-later
import QtQuick
import dev.pairlume

ListView {
    id: l
    required property Texts texts
    property string find
    readonly property bool some: find === "" || hits > 0
    property int hits: 0
    signal chosen(var thread)
    function fits(t) { const f = find.trim().toLowerCase(); return f === "" || (t.name + " " + t.address + " " + t.snippet).toLowerCase().includes(f) || (f.replace(/[ -]/g, "").length > 2 && t.address.replace(/[ -]/g, "").includes(f.replace(/[ -]/g, ""))) }
    function count2() { let n = 0; for (let i = 0; i < texts.threads.count; i++) if (fits(texts.threads.get(i))) n++; hits = n }
    onFindChanged: count2()
    onCountChanged: count2()
    clip: true
    model: texts.threads
    boundsBehavior: Flickable.StopAtBounds
    cacheBuffer: 600
    onAtYEndChanged: if (atYEnd && find === "") texts.older()
    function when(ms) {
        const d = new Date(ms), now = new Date()
        if (d.toDateString() === now.toDateString()) return Qt.formatTime(d, "HH:mm")
        if (new Date(now - 864e5).toDateString() === d.toDateString()) return Tr.t("Yesterday")
        return now - d < 6 * 864e5 ? d.toLocaleDateString(Qt.locale(), "dddd") : d.toLocaleDateString(Qt.locale(), d.getFullYear() === now.getFullYear() ? "d MMM" : "d MMM yyyy")
    }
    move: Transition { NumberAnimation { property: "y"; duration: Theme.normal; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.smooth } }
    moveDisplaced: move
    displaced: move
    delegate: Item {
        id: row
        required property var model
        readonly property bool here: model.id === l.texts.open
        readonly property bool fit: l.fits(model)
        width: l.width
        height: fit ? 74 : 0
        visible: fit
        Accessible.role: Accessible.ListItem
        Accessible.name: l.texts.title(model) + ", " + model.snippet
        Rectangle {
            anchors { fill: parent; topMargin: 2; bottomMargin: 2 }
            radius: 22
            color: row.here ? Theme.accent : Theme.fade(Theme.text, m.containsMouse ? 0.07 : 0)
            Behavior on color { ColorAnimation { duration: Theme.quick } }
        }
        Avatar {
            id: av
            x: 12
            width: 50
            height: 50
            anchors.verticalCenter: parent.verticalCenter
            name: l.texts.title(row.model)
            address: row.model.address
            photo: l.texts.face(row.model.address)
            unread: row.model.unread
            scale: m.pressed ? 0.94 : 1
            Behavior on scale { NumberAnimation { duration: 240; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.spring } }
        }
        Text {
            id: who
            anchors { left: av.right; leftMargin: 13; right: time.left; rightMargin: 8; top: parent.top; topMargin: 15 }
            text: l.texts.title(row.model)
            textFormat: Text.PlainText
            elide: Text.ElideRight
            color: row.here ? Theme.ink : Theme.text
            font.pixelSize: 15
            font.weight: row.model.unread > 0 ? Font.Bold : Font.DemiBold
        }
        Text { id: time; anchors { right: parent.right; rightMargin: 16; baseline: who.baseline } text: l.when(row.model.date); color: row.here ? Theme.fade(Theme.ink, 0.7) : Theme.dim; font.pixelSize: 12 }
        Text {
            anchors { left: who.left; right: parent.right; rightMargin: 16; top: who.bottom; topMargin: 3 }
            text: row.model.snippet.replace(/\s+/g, " ")
            textFormat: Text.PlainText
            elide: Text.ElideRight
            color: row.here ? Theme.fade(Theme.ink, 0.75) : row.model.unread > 0 ? Theme.text : Theme.dim
            font.pixelSize: 13
        }
        MouseArea { id: m; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: l.chosen({ id: row.model.id, name: row.model.name, address: row.model.address }) }
    }
}
