// SPDX-License-Identifier: GPL-3.0-or-later
import QtQuick
import dev.pairlume

// What was said. Mine is in the accent color.
ListView {
    id: l
    required property Texts texts
    readonly property real room: Math.min(width, 760)
    clip: true
    model: texts.messages
    boundsBehavior: Flickable.StopAtBounds
    cacheBuffer: 800
    // few messages: they stand by the line one writes in
    header: Item { width: 1; height: l.pad }
    property real pad: 8
    function settle() {
        const p = Math.max(8, height - (contentHeight - pad))
        if (Math.abs(p - pad) > 0.5) pad = p
        if (pinned) positionViewAtEnd()
    }
    footer: Item { width: 1; height: 8 }
    // stays at the newest one, unless someone is reading further up
    property bool pinned: true
    onMovementEnded: pinned = contentHeight + originY - contentY - height < 60
    onContentHeightChanged: Qt.callLater(settle)
    onHeightChanged: Qt.callLater(settle)
    onAtYBeginningChanged: if (atYBeginning && moving) texts.earlier()
    Connections { target: l.texts; function onOpenChanged() { l.pinned = true } }
    function stamp(ms) {
        const d = new Date(ms), now = new Date(), t = Qt.formatTime(d, "HH:mm")
        if (d.toDateString() === now.toDateString()) return t
        if (new Date(now - 864e5).toDateString() === d.toDateString()) return Tr.t("Yesterday") + " " + t
        return d.toLocaleDateString(Qt.locale(), d.getFullYear() === now.getFullYear() ? "d MMMM" : "d MMMM yyyy") + " " + t
    }
    delegate: Item {
        id: row
        required property var model
        required property int index
        // neighbours are looked up again when the number of messages changes
        readonly property var above: { l.texts.messages.count; return index > 0 ? l.texts.messages.get(index - 1) : null }
        readonly property bool pause: !above || model.date - above.date > 18e5 || new Date(above.date).toDateString() !== new Date(model.date).toDateString()
        readonly property bool turn: pause || above.out !== model.out
        readonly property bool sad: model.state === "failed" || model.state === "unsure"
        width: l.width
        height: bubble.y + bubble.height + (note.visible ? 22 : 0)
        Text {
            visible: row.pause
            anchors.horizontalCenter: parent.horizontalCenter
            y: 14
            text: l.stamp(row.model.date)
            color: Theme.dim
            font.pixelSize: 12
        }
        Rectangle {
            id: bubble
            x: row.model.out ? (l.width + l.room) / 2 - width : (l.width - l.room) / 2
            y: row.pause ? 38 : row.turn ? 10 : 4
            width: body.width + 32
            height: body.height + 21
            radius: 21
            color: row.model.state === "failed" ? Theme.mix(Theme.surface, Theme.bad, 0.3) : row.model.out ? Theme.accent : Theme.mix(Theme.surface, Theme.accent, 0.14)
            opacity: row.model.state === "going" ? 0.6 : 1
            Behavior on opacity { NumberAnimation { duration: Theme.quick } }
            transformOrigin: row.model.out ? Item.BottomRight : Item.BottomLeft
            Component.onCompleted: if (row.model.fresh) pop.start()
            NumberAnimation { id: pop; target: bubble; property: "scale"; from: 0.5; to: 1; duration: Theme.normal; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.spring }
            TextEdit {
                id: body
                x: 16
                y: 10
                width: Math.min(Math.ceil(whole.implicitWidth) + 1, l.room * 0.74 - 32)
                readOnly: true
                selectByMouse: true
                text: row.model.body
                textFormat: TextEdit.PlainText
                wrapMode: TextEdit.Wrap
                color: row.model.out && row.model.state !== "failed" ? Theme.ink : Theme.text
                selectionColor: row.model.out ? Theme.ink : Theme.accent
                selectedTextColor: row.model.out ? Theme.accent : Theme.ink
                font { pixelSize: 14; weight: row.model.out ? Font.Medium : Font.Normal }
            }
            // how wide it would be on one line
            Text { id: whole; visible: false; text: row.model.body; textFormat: Text.PlainText; font: body.font }
        }
        Text {
            id: note
            anchors { top: bubble.bottom; topMargin: 4 }
            x: row.model.out ? (l.width + l.room) / 2 - width - 6 : 6
            visible: row.sad
            text: row.model.state === "failed" ? Tr.t("Not sent") : Tr.t("Not known if it was sent: look on the phone")
            color: Theme.bad
            font.pixelSize: 12
        }
    }
}
