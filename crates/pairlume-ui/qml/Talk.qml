// SPDX-License-Identifier: GPL-3.0-or-later
import QtQuick
import dev.pairlume

Item {
    id: t
    required property Texts texts
    property bool back: true
    signal goBack
    readonly property bool some: texts.head !== null
    function day(ms) { return new Date(ms).toDateString() }

    Item {
        id: top
        width: parent.width
        height: 64
        visible: t.some
        Pill { id: b; visible: t.back; text: "‹"; implicitWidth: 42; anchors { left: parent.left; leftMargin: 12; verticalCenter: parent.verticalCenter } onClicked: t.goBack(); Accessible.name: qsTr("Back") }
        Avatar { id: av; anchors { left: t.back ? b.right : parent.left; leftMargin: 14; verticalCenter: parent.verticalCenter } width: 40; height: 40; name: t.some ? t.texts.title(t.texts.head) : "" }
        Column {
            anchors { left: av.right; leftMargin: 12; right: parent.right; rightMargin: 14; verticalCenter: parent.verticalCenter }
            Text { width: parent.width; elide: Text.ElideRight; textFormat: Text.PlainText; text: t.some ? t.texts.title(t.texts.head) : ""; color: Theme.text; font.pixelSize: 17; font.weight: Font.Bold }
            Text { width: parent.width; elide: Text.ElideRight; textFormat: Text.PlainText; visible: t.some && t.texts.head.name !== ""; text: t.some ? t.texts.head.address : ""; color: Theme.dim; font.pixelSize: 12 }
        }
    }
    ListView {
        id: l
        anchors { top: top.bottom; bottom: compose.top; bottomMargin: 8; left: parent.left; right: parent.right; leftMargin: 16; rightMargin: 16 }
        clip: true
        spacing: 3
        model: t.texts.messages
        boundsBehavior: Flickable.StopAtBounds
        cacheBuffer: 600
        // stays at the newest one, unless someone is reading further up
        property bool pinned: true
        onMovementEnded: pinned = contentHeight - contentY - height < 60
        onContentHeightChanged: if (pinned) Qt.callLater(positionViewAtEnd)
        onHeightChanged: if (pinned) Qt.callLater(positionViewAtEnd)
        onAtYBeginningChanged: if (atYBeginning && moving) t.texts.earlier()
        Connections { target: t.texts; function onOpenChanged() { l.pinned = true } }
        delegate: Item {
            id: row
            required property var model
            required property int index
            readonly property var above: index > 0 ? t.texts.messages.get(index - 1) : null
            readonly property bool newDay: above === null || t.day(above.date) !== t.day(model.date)
            readonly property bool first: newDay || above.out !== model.out
            width: l.width
            height: bubble.height + (newDay ? 40 : 0) + (first && !newDay ? 8 : 0) + (note.visible ? 18 : 0)
            Text {
                visible: row.newDay
                anchors { horizontalCenter: parent.horizontalCenter; top: parent.top; topMargin: 12 }
                text: new Date(row.model.date).toLocaleDateString(Qt.locale(), "d MMMM")
                color: Theme.dim
                font.pixelSize: 12
            }
            Rectangle {
                id: bubble
                anchors { right: row.model.out ? parent.right : undefined; left: row.model.out ? undefined : parent.left; bottom: note.visible ? note.top : parent.bottom }
                width: Math.min(body.implicitWidth + 28, l.width * 0.78)
                height: body.height + 18
                radius: 19
                color: row.model.out ? Theme.accent : Theme.fade(Theme.text, 0.1)
                opacity: row.model.state === "going" ? 0.65 : 1
                Behavior on opacity { NumberAnimation { duration: Theme.quick } }
                transformOrigin: row.model.out ? Item.BottomRight : Item.BottomLeft
                scale: 1
                Component.onCompleted: if (row.model.fresh) { scale = 0.5; pop.start() }
                NumberAnimation { id: pop; target: bubble; property: "scale"; to: 1; duration: 420; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.spring }
                TextEdit {
                    id: body
                    x: 14
                    y: 9
                    width: Math.min(implicitWidth, l.width * 0.78 - 28)
                    readOnly: true
                    selectByMouse: true
                    text: row.model.body
                    textFormat: TextEdit.PlainText
                    wrapMode: TextEdit.Wrap
                    color: row.model.out ? Theme.ink : Theme.text
                    selectionColor: Theme.accent2
                    font.pixelSize: 14
                }
            }
            Text {
                id: note
                visible: row.model.state === "failed" || row.model.state === "unsure" || row.index === t.texts.messages.count - 1
                anchors { right: row.model.out ? parent.right : undefined; left: row.model.out ? undefined : parent.left; bottom: parent.bottom; margins: 2 }
                text: row.model.state === "failed" ? qsTr("Not sent") : row.model.state === "unsure" ? qsTr("Not known if it was sent: look on the phone")
                    : row.model.state === "going" ? qsTr("Sending") : Qt.formatTime(new Date(row.model.date), "HH:mm")
                color: row.model.state === "failed" || row.model.state === "unsure" ? Theme.bad : Theme.dim
                font.pixelSize: 11
            }
        }
    }
    Rectangle {
        id: compose
        visible: t.some
        anchors { left: parent.left; right: parent.right; bottom: parent.bottom; margins: 14 }
        height: Math.min(150, Math.max(48, box.contentHeight + 26))
        radius: 24
        color: Theme.fade(Theme.text, 0.08)
        border { width: box.activeFocus ? 2 : 0; color: Theme.fade(Theme.accent, 0.7) }
        Behavior on height { NumberAnimation { duration: Theme.quick; easing.type: Easing.OutCubic } }
        Flickable {
            id: scroll
            anchors { left: parent.left; leftMargin: 18; right: go.left; rightMargin: 10; top: parent.top; bottom: parent.bottom; topMargin: 13; bottomMargin: 13 }
            clip: true
            contentHeight: box.contentHeight
            TextEdit {
                id: box
                width: scroll.width
                color: Theme.text
                wrapMode: TextEdit.Wrap
                textFormat: TextEdit.PlainText
                selectByMouse: true
                selectionColor: Theme.accent2
                font.pixelSize: 14
                Accessible.name: qsTr("Message")
                onCursorRectangleChanged: {
                    if (cursorRectangle.y < scroll.contentY) scroll.contentY = cursorRectangle.y
                    else if (cursorRectangle.y + cursorRectangle.height > scroll.contentY + scroll.height) scroll.contentY = cursorRectangle.y + cursorRectangle.height - scroll.height
                }
                Keys.onPressed: e => { if ((e.key === Qt.Key_Return || e.key === Qt.Key_Enter) && !(e.modifiers & Qt.ShiftModifier)) { e.accepted = true; go.clicked() } }
                Text { visible: box.text === "" && box.preeditText === ""; text: qsTr("Message"); color: Theme.dim; font: box.font }
            }
        }
        Pill {
            id: go
            anchors { right: parent.right; rightMargin: 5; bottom: parent.bottom; bottomMargin: 5 }
            implicitWidth: 58
            implicitHeight: 38
            text: "➤"
            filled: true
            enabled: box.text.trim() !== "" && box.text.length <= 2000 && t.texts.online
            Accessible.name: qsTr("Send")
            onClicked: if (enabled) { l.pinned = true; t.texts.send(box.text); box.clear() }
        }
    }
    Text { visible: !t.some; anchors.centerIn: parent; text: qsTr("Choose a conversation"); color: Theme.dim; font.pixelSize: 15 }
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
