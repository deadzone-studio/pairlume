// SPDX-License-Identifier: GPL-3.0-or-later
import QtQuick
import dev.pairlume

// One notification of the phone as a banner at the top, like a text on an iPhone: the app's icon big, who or what,
// two lines of words. A click opens it into the conversation: the words in a bubble, a line to answer in, its buttons.
// A code in it has its own button on the banner already; a download shows its bar.
Rectangle {
    id: n
    required property Texts texts
    required property var model
    readonly property var actions: { try { return JSON.parse(model.actions) } catch (e) { return [] } }
    readonly property int replyAt: { for (let i = 0; i < actions.length; i++) if (actions[i].reply) return i; return -1 }
    readonly property string code: texts.code(model.title + " " + model.text)
    readonly property bool bar: model.pMax > 0 || model.pBusy
    property bool open: false
    property bool copied: false
    readonly property bool busy: open || hover.hovered
    signal closed
    width: 420
    height: col.height + 24
    radius: open ? 26 : 22
    color: Theme.fade(Theme.surface, Math.max(0.94, Theme.glass))
    border.color: Theme.fade(Theme.text, 0.1)
    Behavior on height { NumberAnimation { duration: Theme.normal; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.spring } }
    HoverHandler { id: hover }
    TextEdit { id: clip; visible: false }
    function copy(t) { clip.text = t; clip.selectAll(); clip.copy(); copied = true }
    // the banner opens with a click on it (not on a button)
    TapHandler { onTapped: if (!n.open && !n.bar) n.open = true }

    Column {
        id: col
        x: 12
        y: 12
        width: parent.width - 24
        spacing: 8

        // ---------- the banner ----------
        Row {
            width: parent.width
            spacing: 12
            Rectangle {
                width: n.open ? 30 : 40; height: width
                radius: width * 0.26
                color: Theme.fade(Theme.text, 0.1)
                Image { anchors.fill: parent; anchors.margins: 2; source: n.texts.notifIcon(n.model.app); sourceSize: Qt.size(64, 64); smooth: true; visible: status === Image.Ready }
                Text { anchors.centerIn: parent; visible: n.texts.notifIcon(n.model.app) === ""; text: (n.model.appName || "?").slice(0, 1).toUpperCase(); color: Theme.text; font { pixelSize: 15; weight: Font.DemiBold } }
            }
            Column {
                width: parent.width - (n.open ? 42 : 52)
                spacing: 1
                Row {
                    width: parent.width
                    Text { width: parent.width - when.width - 8; text: n.model.title || n.model.appName; textFormat: Text.PlainText; elide: Text.ElideRight; color: Theme.text; font { pixelSize: 15; weight: Font.DemiBold } }
                    Item { width: 8; height: 1 }
                    Text { id: when; text: n.bar && !n.model.pBusy ? Math.round(100 * Math.min(1, n.model.pValue / Math.max(1, n.model.pMax))) + "%" : n.texts.ago(n.model.when); color: Theme.dim; font.pixelSize: 12; anchors.baseline: parent.children[0].baseline }
                }
                // closed: two lines; open: the app and the time, the words go into the bubble
                Text {
                    width: parent.width
                    visible: !n.open && text !== ""
                    text: n.model.text
                    textFormat: Text.PlainText
                    wrapMode: Text.Wrap
                    maximumLineCount: 2
                    elide: Text.ElideRight
                    color: Theme.text
                    font.pixelSize: 14
                }
                Text { visible: n.open; text: n.model.appName; textFormat: Text.PlainText; color: Theme.dim; font.pixelSize: 12 }
                ProgressLine { width: parent.width; visible: n.bar; max: n.model.pMax; value: n.model.pValue; busy: n.model.pBusy; height: 14; figures: false }
            }
        }
        Pill {
            visible: n.code !== "" && !n.open
            x: 52
            filled: true
            text: n.copied ? Tr.t("Copied") : Tr.t("Copy %1").arg(n.code)
            onClicked: n.copy(n.code)
        }

        // ---------- opened: the conversation ----------
        Rectangle {
            visible: n.open && n.model.text !== ""
            width: Math.min(parent.width * 0.86, said.implicitWidth + 26)
            height: said.height + 16
            radius: 18
            bottomLeftRadius: 6
            color: Theme.fade(Theme.text, 0.1)
            Text { id: said; x: 13; y: 8; width: Math.min(implicitWidth, n.width * 0.86 - 50); text: n.model.text; textFormat: Text.PlainText; wrapMode: Text.Wrap; color: Theme.text; font.pixelSize: 14 }
        }
        Row {
            visible: n.open && n.replyAt >= 0
            width: parent.width
            spacing: 8
            Rectangle {
                width: parent.width - send.width - 8
                height: 38
                radius: 19
                color: "transparent"
                border { width: 1; color: answer.activeFocus ? Theme.accent : Theme.fade(Theme.text, 0.18) }
                TextInput {
                    id: answer
                    anchors { fill: parent; leftMargin: 14; rightMargin: 14 }
                    verticalAlignment: TextInput.AlignVCenter
                    color: Theme.text
                    selectionColor: Theme.accent
                    selectedTextColor: Theme.ink
                    font.pixelSize: 14
                    clip: true
                    Accessible.name: Tr.t("Your answer")
                    onVisibleChanged: if (visible) forceActiveFocus()
                    onAccepted: send.go()
                    Keys.onEscapePressed: { text = ""; n.open = false }
                    Text { visible: answer.text === "" && answer.preeditText === ""; anchors.verticalCenter: parent.verticalCenter; width: parent.width; elide: Text.ElideRight; text: Tr.t("Answer %1").arg(n.model.title); textFormat: Text.PlainText; color: Theme.dim; font: answer.font }
                }
            }
            // the round send button of a text
            Rectangle {
                id: send
                width: 38; height: 38; radius: 19
                color: answer.text.trim() !== "" ? Theme.accent : Theme.fade(Theme.text, 0.12)
                Accessible.role: Accessible.Button
                Accessible.name: Tr.t("Send")
                function go() { if (answer.text.trim() === "") return; n.texts.notifDo(n.model.key, "reply", n.replyAt, answer.text); answer.text = ""; n.closed() }
                Text { anchors.centerIn: parent; text: "↑"; color: answer.text.trim() !== "" ? Theme.ink : Theme.dim; font { pixelSize: 18; weight: Font.Bold } }
                MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: send.go() }
            }
        }
        Flow {
            visible: n.open
            width: parent.width
            spacing: 8
            Pill { visible: n.code !== ""; filled: true; text: n.copied ? Tr.t("Copied") : Tr.t("Copy %1").arg(n.code); onClicked: n.copy(n.code) }
            Repeater {
                model: n.actions
                Pill {
                    required property var modelData
                    required property int index
                    visible: !modelData.reply
                    text: modelData.title || ""
                    onClicked: { n.texts.notifDo(n.model.key, "action", index); n.closed() }
                }
            }
            Pill { text: Tr.t("Dismiss"); onClicked: { n.texts.notifDo(n.model.key, "dismiss"); n.closed() } }
        }
    }
}
