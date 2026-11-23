// SPDX-License-Identifier: GPL-3.0-or-later
import QtQuick
import dev.pairlume

ListView {
    id: l
    required property Texts texts
    property string find
    // only those with something to read
    property bool fresh: false
    signal chosen(var thread)
    // rows that are shown, as indexes of the model
    property var shown: []
    readonly property int hits: shown.length
    function fits(t) {
        if (fresh && t.unread === 0 && t.id !== texts.open) return false
        const f = find.trim().toLowerCase(), bare = f.replace(/[ +-]/g, "")
        return f === "" || (t.name + " " + t.address + " " + t.snippet).toLowerCase().includes(f) || (/^[0-9]{3,}$/.test(bare) && t.address.replace(/[ +-]/g, "").includes(bare))
    }
    function sieve() { const r = []; for (let i = 0; i < texts.threads.count; i++) if (fits(texts.threads.get(i))) r.push(i); shown = r }
    function pickNth(n) { const t = texts.threads.get(shown[n] ?? -1); if (t) chosen({ id: t.id, name: t.name, address: t.address }) }
    function step(d) {
        let at = -1
        for (let i = 0; i < shown.length; i++) if (texts.threads.get(shown[i]).id === texts.open) at = i
        pickNth(Math.max(0, Math.min(shown.length - 1, at < 0 ? 0 : at + d)))
    }
    onFindChanged: sieve()
    onFreshChanged: sieve()
    onCountChanged: sieve()
    Connections { target: l.texts; function onLoadingChanged() { l.sieve() } function onWaitingChanged() { l.sieve() } }
    clip: true
    model: texts.threads
    boundsBehavior: Flickable.StopAtBounds
    cacheBuffer: 600
    onAtYEndChanged: if (atYEnd && find === "") texts.older()
    move: Transition { NumberAnimation { property: "y"; duration: Theme.normal; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.smooth } }
    moveDisplaced: move
    displaced: move
    delegate: Item {
        id: row
        required property var model
        readonly property bool here: model.id === l.texts.open
        readonly property bool fit: { l.find; l.fresh; return l.fits(model) }
        width: l.width
        height: fit ? 66 : 0
        visible: fit
        Accessible.role: Accessible.ListItem
        Accessible.name: l.texts.title(model) + ", " + model.snippet
        Rectangle {
            anchors { fill: parent; topMargin: 1; bottomMargin: 1 }
            radius: 22
            color: row.here ? Theme.fade(Theme.accent, 0.18) : Theme.fade(Theme.text, m.containsMouse ? 0.06 : 0)
            Behavior on color { ColorAnimation { duration: Theme.quick } }
        }
        Avatar {
            id: av
            x: 10
            width: 50
            anchors.verticalCenter: parent.verticalCenter
            name: l.texts.title(row.model)
            address: row.model.address
            photo: l.texts.face(row.model.address)
            ring: row.model.unread > 0
        }
        Text {
            id: who
            anchors { left: av.right; leftMargin: 13; right: time.left; rightMargin: 8; top: parent.top; topMargin: 12 }
            text: l.texts.title(row.model)
            textFormat: Text.PlainText
            elide: Text.ElideRight
            color: Theme.text
            font { pixelSize: 15; weight: Font.DemiBold }
        }
        Text { id: time; anchors { right: parent.right; rightMargin: 14; baseline: who.baseline } text: l.texts.when(row.model.date); color: Theme.dim; font.pixelSize: 12 }
        Text {
            anchors { left: who.left; right: many.visible ? many.left : parent.right; rightMargin: many.visible ? 8 : 14; top: who.bottom; topMargin: 2 }
            text: row.model.snippet.replace(/\s+/g, " ")
            textFormat: Text.PlainText
            elide: Text.ElideRight
            color: row.model.unread > 0 ? Theme.text : Theme.dim
            font.pixelSize: 13
        }
        Text { id: many; visible: row.model.unread > 1; anchors { right: parent.right; rightMargin: 14; bottom: parent.bottom; bottomMargin: 14 } text: row.model.unread; color: Theme.accent; font { pixelSize: 13; weight: Font.Bold } }
        MouseArea { id: m; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: l.chosen({ id: row.model.id, name: row.model.name, address: row.model.address }) }
    }
}
