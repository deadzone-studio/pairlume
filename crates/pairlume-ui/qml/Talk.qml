// SPDX-License-Identifier: GPL-3.0-or-later
import QtQuick
import dev.pairlume

// One conversation. The messages go under the glass at the top and at the bottom.
Item {
    id: t
    required property Texts texts
    property bool back: true
    signal goBack
    readonly property bool some: texts.head !== null
    readonly property string who: some ? texts.title(texts.head) : ""
    function day(ms) {
        const d = new Date(ms), now = new Date()
        if (d.toDateString() === now.toDateString()) return Tr.t("Today")
        if (new Date(now - 864e5).toDateString() === d.toDateString()) return Tr.t("Yesterday")
        return d.toLocaleDateString(Qt.locale(), d.getFullYear() === now.getFullYear() ? "dddd, d MMMM" : "d MMMM yyyy")
    }

    ListView {
        id: l
        anchors { fill: parent; leftMargin: 18; rightMargin: 18 }
        clip: true
        model: t.texts.messages
        boundsBehavior: Flickable.StopAtBounds
        cacheBuffer: 800
        header: Item { width: 1; height: 104 }
        footer: Item { width: 1; height: compose.height + 34 }
        // stays at the newest one, unless someone is reading further up
        property bool pinned: true
        onMovementEnded: pinned = contentHeight + originY - contentY - height < 80
        onContentHeightChanged: if (pinned) Qt.callLater(positionViewAtEnd)
        onHeightChanged: if (pinned) Qt.callLater(positionViewAtEnd)
        onAtYBeginningChanged: if (atYBeginning && moving) t.texts.earlier()
        Connections { target: t.texts; function onOpenChanged() { l.pinned = true } }
        delegate: Item {
            id: row
            required property var model
            required property int index
            // neighbours are looked up again when the number of messages changes
            readonly property var above: { t.texts.messages.count; return index > 0 ? t.texts.messages.get(index - 1) : null }
            readonly property var below: index + 1 < t.texts.messages.count ? t.texts.messages.get(index + 1) : null
            readonly property bool newDay: !above || new Date(above.date).toDateString() !== new Date(model.date).toDateString()
            readonly property bool pause: !newDay && model.date - above.date > 36e5
            readonly property bool first: newDay || pause || above.out !== model.out
            readonly property bool last: !below || below.out !== model.out || below.date - model.date > 36e5
            readonly property bool out: model.out
            readonly property bool sad: model.state === "failed" || model.state === "unsure"
            width: l.width
            height: bubble.height + (newDay || pause ? 42 : first ? 12 : 3) + (note.visible ? 20 : 0)
            Text {
                visible: row.newDay || row.pause
                anchors { horizontalCenter: parent.horizontalCenter; top: parent.top; topMargin: 15 }
                text: (row.newDay ? t.day(row.model.date) + "  " : "") + Qt.formatTime(new Date(row.model.date), "HH:mm")
                color: Theme.dim
                font.pixelSize: 11
                font.weight: Font.Medium
            }
            Rectangle {
                id: bubble
                readonly property real r: Math.min(20, height / 2)
                anchors { right: row.out ? parent.right : undefined; left: row.out ? undefined : parent.left; bottom: note.visible ? note.top : parent.bottom; bottomMargin: note.visible ? 3 : 0 }
                width: Math.min(body.implicitWidth + 30, l.width * 0.72)
                height: body.height + 20
                topLeftRadius: row.out || row.first ? r : 7
                bottomLeftRadius: row.out ? r : row.last ? 5 : 7
                topRightRadius: !row.out || row.first ? r : 7
                bottomRightRadius: !row.out ? r : row.last ? 5 : 7
                gradient: Gradient {
                    GradientStop { position: 0; color: row.out ? Theme.accent : Theme.fade(Theme.text, 0.15) }
                    GradientStop { position: 1; color: row.out ? Theme.mix(Theme.accent, Theme.accent2, 0.3) : Theme.fade(Theme.text, 0.1) }
                }
                opacity: row.model.state === "going" ? 0.6 : 1
                Behavior on opacity { NumberAnimation { duration: Theme.quick } }
                transformOrigin: row.out ? Item.BottomRight : Item.BottomLeft
                Component.onCompleted: if (row.model.fresh) { scale = 0.4; pop.start() }
                NumberAnimation { id: pop; target: bubble; property: "scale"; to: 1; duration: 480; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.spring }
                TextEdit {
                    id: body
                    x: 15
                    y: 10
                    width: Math.min(implicitWidth, l.width * 0.72 - 30)
                    readOnly: true
                    selectByMouse: true
                    text: row.model.body
                    textFormat: TextEdit.PlainText
                    wrapMode: TextEdit.Wrap
                    color: row.out ? Theme.ink : Theme.text
                    selectionColor: row.out ? Theme.ink : Theme.accent
                    selectedTextColor: row.out ? Theme.accent : Theme.ink
                    font.pixelSize: 15
                }
            }
            Text {
                id: note
                visible: row.sad || row.model.state === "going"
                anchors { right: row.out ? parent.right : undefined; left: row.out ? undefined : parent.left; bottom: parent.bottom; rightMargin: 4; leftMargin: 4 }
                text: row.model.state === "failed" ? Tr.t("Not sent") : row.model.state === "unsure" ? Tr.t("Not known if it was sent: look on the phone") : Tr.t("Sending")
                color: row.sad ? Theme.bad : Theme.dim
                font.pixelSize: 11
            }
        }
    }

    // who
    Round { visible: t.back && t.some; x: 14; y: 14; path: "M14.5 5.5 8 12l6.5 6.5"; label: Tr.t("Back"); onClicked: t.goBack() }
    Column {
        visible: t.some
        anchors { horizontalCenter: parent.horizontalCenter; top: parent.top; topMargin: 12 }
        spacing: -9
        Avatar { anchors.horizontalCenter: parent.horizontalCenter; width: 58; height: 58; z: 1; name: t.who; address: t.some ? t.texts.head.address : ""; photo: t.some ? t.texts.face(t.texts.head.address) : "" }
        Rectangle {
            anchors.horizontalCenter: parent.horizontalCenter
            z: 2
            width: Math.min(nm.implicitWidth + 28, t.width - 140)
            height: 28
            radius: 14
            color: Theme.mix(Theme.surface, Theme.text, 0.13)
            border { width: 1; color: Theme.fade(Theme.text, 0.1) }
            Text { id: nm; anchors.centerIn: parent; width: parent.width - 24; horizontalAlignment: Text.AlignHCenter; elide: Text.ElideRight; textFormat: Text.PlainText; text: t.who; color: Theme.text; font.pixelSize: 13; font.weight: Font.DemiBold }
        }
    }

    // what to say
    Rectangle {
        id: compose
        visible: t.some
        anchors { left: parent.left; right: parent.right; bottom: parent.bottom; margins: 16 }
        height: Math.min(150, Math.max(48, box.contentHeight + 28))
        radius: 24
        color: Theme.mix(Theme.surface, Theme.text, 0.1)
        border { width: 1; color: box.activeFocus ? Theme.fade(Theme.accent, 0.6) : Theme.fade(Theme.text, 0.12) }
        Behavior on height { NumberAnimation { duration: Theme.quick; easing.type: Easing.OutCubic } }
        Behavior on border.color { ColorAnimation { duration: Theme.quick } }
        Flickable {
            id: scroll
            anchors { left: parent.left; leftMargin: 20; right: go.left; rightMargin: 10; top: parent.top; bottom: parent.bottom; topMargin: 14; bottomMargin: 14 }
            clip: true
            contentHeight: box.contentHeight
            TextEdit {
                id: box
                width: scroll.width
                color: Theme.text
                wrapMode: TextEdit.Wrap
                textFormat: TextEdit.PlainText
                selectByMouse: true
                selectionColor: Theme.accent
                selectedTextColor: Theme.ink
                font.pixelSize: 15
                Accessible.name: Tr.t("Message")
                onCursorRectangleChanged: {
                    if (cursorRectangle.y < scroll.contentY) scroll.contentY = cursorRectangle.y
                    else if (cursorRectangle.y + cursorRectangle.height > scroll.contentY + scroll.height) scroll.contentY = cursorRectangle.y + cursorRectangle.height - scroll.height
                }
                Keys.onPressed: e => { if ((e.key === Qt.Key_Return || e.key === Qt.Key_Enter) && !(e.modifiers & Qt.ShiftModifier)) { e.accepted = true; go.clicked() } }
                Text { visible: box.text === "" && box.preeditText === ""; text: Tr.t("Message"); color: Theme.dim; font: box.font }
            }
        }
        Round {
            id: go
            readonly property bool can: box.text.trim() !== "" && box.text.length <= 2000 && t.texts.online
            anchors { right: parent.right; rightMargin: 6; bottom: parent.bottom; bottomMargin: 6 }
            width: 36
            height: 36
            filled: true
            enabled: can
            path: "M12 19V5M6 11l6-6 6 6"
            label: Tr.t("Send")
            onClicked: if (can) { l.pinned = true; t.texts.send(box.text); box.clear() }
        }
    }
    Column {
        visible: !t.some
        anchors.centerIn: parent
        spacing: 16
        Glass {
            anchors.horizontalCenter: parent.horizontalCenter
            width: 92
            height: 70
            radius: 26
            Row { anchors.centerIn: parent; spacing: 9; Repeater { model: 3; Rectangle { required property int index; width: 11; height: 11; radius: 5.5; color: Theme.accent; opacity: 0.35 + 0.3 * index } } }
        }
        Text { text: Tr.t("Choose a conversation"); color: Theme.dim; font.pixelSize: 15 }
    }
    // a draft belongs to its conversation
    property var drafts: ({})
    property int was: -1
    Connections {
        target: t.texts
        function onOpenChanged() {
            if (t.was >= 0) t.drafts[t.was] = box.text
            t.was = t.texts.open
            box.text = t.texts.open >= 0 ? (t.drafts[t.texts.open] || "") : ""
            if (t.texts.open >= 0) { box.cursorPosition = box.length; box.forceActiveFocus() }
        }
    }
}
