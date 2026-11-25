// SPDX-License-Identifier: GPL-3.0-or-later
import QtQuick
import dev.pairlume

// One notification of the phone: the app, who or what, the words, its buttons; a button that takes an answer opens a
// line to write it in. The same glass and light edge as the pairing card, smaller.
Rectangle {
    id: n
    required property Texts texts
    required property var model
    readonly property var actions: { try { return JSON.parse(model.actions) } catch (e) { return [] } }
    // a code in it (a bank, a login): copied with one click instead of answered
    readonly property string code: texts.code(model.title + " " + model.text)
    property bool copied: false
    property int replying: -1
    readonly property bool busy: replying >= 0 || hover.hovered
    signal closed
    width: 380
    height: col.height + 32
    radius: 22
    color: Theme.fade(Theme.surface, Math.max(0.94, Theme.glass))
    border.color: Theme.fade(Theme.text, 0.12)
    Rectangle {
        anchors { fill: parent; margins: 1 }
        radius: 21
        gradient: Gradient {
            GradientStop { position: 0; color: Theme.fade(Theme.text, 0.08) }
            GradientStop { position: 0.6; color: Theme.fade(Theme.text, 0) }
        }
    }
    HoverHandler { id: hover }
    TextEdit { id: clip; visible: false }
    Column {
        id: col
        x: 18
        y: 16
        width: parent.width - 36
        spacing: 6
        Row {
            spacing: 8
            width: parent.width
            Image {
                width: 20; height: 20
                source: n.texts.notifIcon(n.model.app)
                sourceSize: Qt.size(64, 64)
                smooth: true
                visible: status === Image.Ready
            }
            Text { text: n.model.appName; textFormat: Text.PlainText; color: Theme.dim; font.pixelSize: 12; anchors.verticalCenter: parent.verticalCenter; width: Math.min(implicitWidth, parent.width - 120); elide: Text.ElideRight }
            Text { text: "· " + n.texts.ago(n.model.when); color: Theme.dim; font.pixelSize: 12; anchors.verticalCenter: parent.verticalCenter }
        }
        Text { width: parent.width; visible: text !== ""; text: n.model.title; textFormat: Text.PlainText; elide: Text.ElideRight; color: Theme.text; font { pixelSize: 15; weight: Font.DemiBold } }
        Text { width: parent.width; visible: text !== ""; text: n.model.text; textFormat: Text.PlainText; wrapMode: Text.Wrap; maximumLineCount: 4; elide: Text.ElideRight; color: Theme.text; font.pixelSize: 14; lineHeight: 1.1 }
        ProgressLine { width: parent.width; max: n.model.pMax; value: n.model.pValue; busy: n.model.pBusy; visible: n.model.pMax > 0 || n.model.pBusy }
        Item { width: 1; height: 4 }
        // the buttons of the notification, and ours: dismiss
        Flow {
            width: parent.width
            spacing: 8
            visible: n.replying < 0
            Pill {
                visible: n.code !== ""
                filled: true
                text: n.copied ? Tr.t("Copied") : Tr.t("Copy %1").arg(n.code)
                onClicked: { clip.text = n.code; clip.selectAll(); clip.copy(); n.copied = true }
            }
            Repeater {
                model: n.actions
                Pill {
                    required property var modelData
                    required property int index
                    text: modelData.title || ""
                    filled: index === 0 && !!modelData.reply && n.code === ""
                    onClicked: modelData.reply ? n.replying = index : n.texts.notifDo(n.model.key, "action", index)
                }
            }
            Pill { text: Tr.t("Dismiss"); onClicked: { n.texts.notifDo(n.model.key, "dismiss"); n.closed() } }
        }
        Row {
            width: parent.width
            spacing: 8
            visible: n.replying >= 0
            Rectangle {
                width: parent.width - send.width - 8
                height: 42
                radius: 21
                color: Theme.fade(Theme.text, 0.07)
                border { width: answer.activeFocus ? 2 : 0; color: Theme.accent }
                TextInput {
                    id: answer
                    anchors { fill: parent; leftMargin: 16; rightMargin: 16 }
                    verticalAlignment: TextInput.AlignVCenter
                    color: Theme.text
                    selectionColor: Theme.accent
                    selectedTextColor: Theme.ink
                    font.pixelSize: 14
                    clip: true
                    focus: n.replying >= 0
                    Accessible.name: Tr.t("Your answer")
                    onVisibleChanged: if (visible) forceActiveFocus()
                    onAccepted: send.clicked()
                    Keys.onEscapePressed: { text = ""; n.replying = -1 }
                    Text { visible: answer.text === "" && answer.preeditText === ""; anchors.verticalCenter: parent.verticalCenter; text: Tr.t("Answer %1").arg(n.model.title); textFormat: Text.PlainText; width: parent.width; elide: Text.ElideRight; color: Theme.dim; font: answer.font }
                }
            }
            Pill {
                id: send
                text: Tr.t("Send")
                filled: true
                enabled: answer.text.trim() !== ""
                onClicked: { if (!enabled) return; n.texts.notifDo(n.model.key, "reply", n.replying, answer.text); answer.text = ""; n.replying = -1 }
            }
        }
    }
}
