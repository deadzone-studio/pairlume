// SPDX-License-Identifier: GPL-3.0-or-later
import QtQuick
import dev.pairlume

// What to say, and what it costs: how many texts it will be.
Item {
    id: c
    required property Texts texts
    property alias focused: box.activeFocus
    readonly property var cost: parts(box.text)
    readonly property bool ready: texts.online && box.text.trim() !== "" && box.text.length <= 2000
    implicitHeight: Math.min(132, Math.max(20, box.contentHeight)) + 22
    function go() { if (ready) { texts.send(box.text); box.clear() } }
    Rectangle {
        id: field
        anchors { left: parent.left; right: send.left; rightMargin: 10; top: parent.top; bottom: parent.bottom }
        radius: 21
        color: Theme.fade(Theme.text, 0.07)
        border { width: box.activeFocus ? 2 : 0; color: Theme.accent }
        MouseArea { anchors.fill: parent; cursorShape: Qt.IBeamCursor; onClicked: box.forceActiveFocus() }
    }
    Pill { id: send; anchors { right: parent.right; bottom: parent.bottom } text: Tr.t("Send"); filled: true; enabled: c.ready; onClicked: c.go() }
    function grab() { if (texts.open >= 0) box.forceActiveFocus() }
    // GSM letters: 160 in a text. One other letter (ą, an emoji) and it is 70
    function parts(s) {
        let n = 0, gsm = true
        for (const ch of s) {
            if ("^{}\\[~]|€".includes(ch)) n += 2
            else if (/^[A-Za-z0-9 \n\r@£$¥èéùìòÇØøÅåΔ_ΦΓΛΩΠΨΣΘΞÆæßÉ!"#¤%&'()*+,\-./:;<=>?¡ÄÖÑÜ§¿äöñüà]$/.test(ch)) n += 1
            else { gsm = false; break }
        }
        if (!gsm) n = s.length
        const one = gsm ? 160 : 70, many = gsm ? 153 : 67
        const k = n === 0 ? 0 : n <= one ? 1 : Math.ceil(n / many)
        return { k: k, left: k <= 1 ? one - n : k * many - n, gsm: gsm }
    }
    Flickable {
        id: scroll
        anchors { left: field.left; leftMargin: 18; right: info.left; rightMargin: info.text === "" ? 0 : 10; top: parent.top; bottom: parent.bottom; topMargin: 11; bottomMargin: 11 }
        clip: true
        contentHeight: box.contentHeight
        TextEdit {
            id: box
            width: scroll.width
            enabled: c.texts.open >= 0
            color: Theme.text
            wrapMode: TextEdit.Wrap
            textFormat: TextEdit.PlainText
            selectByMouse: true
            selectionColor: Theme.accent
            selectedTextColor: Theme.ink
            font.pixelSize: 14
            Accessible.name: Tr.t("Message")
            onCursorRectangleChanged: {
                if (cursorRectangle.y < scroll.contentY) scroll.contentY = cursorRectangle.y
                else if (cursorRectangle.y + cursorRectangle.height > scroll.contentY + scroll.height) scroll.contentY = cursorRectangle.y + cursorRectangle.height - scroll.height
            }
            Keys.onPressed: e => {
                if ((e.key === Qt.Key_Return || e.key === Qt.Key_Enter) && !(e.modifiers & Qt.ShiftModifier)) {
                    e.accepted = true
                    c.go()
                }
            }
            Text { visible: box.text === "" && box.preeditText === ""; text: c.texts.head ? Tr.t("Write to %1").arg(c.texts.title(c.texts.head)) : ""; textFormat: Text.PlainText; width: scroll.width; elide: Text.ElideRight; color: Theme.dim; font: box.font }
        }
    }
    Text {
        id: info
        anchors { right: field.right; rightMargin: 18; bottom: field.bottom; bottomMargin: 12 }
        // only when it starts to matter
        text: box.text.length > 2000 ? Tr.t("too long") : c.cost.k > 1 || (c.cost.k === 1 && c.cost.left < 25) ? c.cost.k + " SMS, " + c.cost.left : ""
        color: box.text.length > 2000 ? Theme.bad : Theme.dim
        font.pixelSize: 12
    }
    // a draft belongs to its conversation
    property var drafts: ({})
    property int was: -1
    Connections {
        target: c.texts
        function onOpenChanged() {
            if (c.was >= 0) c.drafts[c.was] = box.text
            c.was = c.texts.open
            box.text = c.texts.open >= 0 ? (c.drafts[c.texts.open] || "") : ""
            if (c.texts.open >= 0) { box.cursorPosition = box.length; box.forceActiveFocus() }
        }
    }
}
