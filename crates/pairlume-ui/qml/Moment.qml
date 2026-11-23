// SPDX-License-Identifier: GPL-3.0-or-later
import QtQuick
import dev.pairlume

// One text, like one step of pairing: whose it is, what it says, what to do. A code gets its digits.
Card {
    id: m
    required property Texts texts
    // { id, name, address, snippet, date }, or null: nobody is waiting
    property var of: null
    readonly property string code: of ? texts.code(of.snippet) : ""
    readonly property bool fits: width > 300
    signal later
    signal reply
    signal copy(string text)
    title: of ? texts.title(of) : texts.online ? texts.deviceName : Tr.t("Not connected")
    line: of ? (code !== "" ? Tr.t("a code, %1").arg(texts.when(of.date)) : texts.ago(of.date))
             : texts.online ? Tr.t("Nobody is waiting") : ""
    Item {
        id: stage
        anchors { horizontalCenter: parent.horizontalCenter; top: parent.top; topMargin: m.below + 8; bottom: pills.top; bottomMargin: 20 }
        width: parent.width
        // the circles of pairing, once, when someone comes
        Item {
            id: rings
            visible: m.of !== null && m.code === ""
            anchors.centerIn: face
            property real t: 1
            NumberAnimation { id: wave; target: rings; property: "t"; from: 0; to: 1; duration: 1100; easing.type: Easing.OutCubic }
            Repeater {
                model: 3
                Rectangle {
                    required property int index
                    anchors.centerIn: parent
                    width: face.width + (36 + index * 50) * rings.t
                    height: width
                    radius: width / 2
                    color: "transparent"
                    border { width: 2; color: Theme.fade(index === 1 ? Theme.accent2 : Theme.accent, 0.5 - index * 0.17) }
                }
            }
        }
        Avatar {
            id: face
            visible: m.of !== null
            anchors.horizontalCenter: parent.horizontalCenter
            y: Math.max(0, (stage.height - used) * 0.4) + (m.code === "" ? 68 : 0)
            readonly property real used: m.code === "" ? 250 + words.height : 180 + words.height
            width: m.code === "" ? 112 : 92
            ring: true
            name: m.of ? m.texts.title(m.of) : ""
            address: m.of ? m.of.address : ""
            photo: m.of ? m.texts.face(m.of.address) : ""
        }
        Loader {
            id: digits
            anchors { horizontalCenter: parent.horizontalCenter; top: face.bottom; topMargin: 30 }
            active: m.code !== ""
            sourceComponent: Digits { code: m.code; cell: Math.min(44, (stage.width - 60) / m.code.length - 10) }
        }
        Text {
            id: words
            anchors { horizontalCenter: parent.horizontalCenter; top: m.code === "" ? face.bottom : digits.bottom; topMargin: m.code === "" ? 84 : 28 }
            width: Math.min(440, stage.width - 72)
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.Wrap
            maximumLineCount: 4
            elide: Text.ElideRight
            textFormat: Text.PlainText
            text: m.of ? m.of.snippet : ""
            color: m.code === "" ? Theme.text : Theme.dim
            font.pixelSize: m.code === "" ? 19 : 14
            lineHeight: 1.15
        }
        // nobody: the phone itself
        Rings { visible: m.of === null && !m.texts.online; on: visible; anchors.centerIn: parent; width: 280; height: 280 }
        Phone { visible: m.of === null; anchors.centerIn: parent; glow: m.texts.online ? 1 : 0; Behavior on glow { NumberAnimation { duration: Theme.normal } } }
        Text {
            visible: m.of === null
            anchors { horizontalCenter: parent.horizontalCenter; bottom: parent.bottom }
            width: stage.width - 72
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.Wrap
            textFormat: Text.PlainText
            text: !m.texts.online ? m.texts.trouble : m.texts.battery >= 0 ? Tr.t("battery %1%").arg(m.texts.battery) + (m.texts.charging ? ", " + Tr.t("charging") : "") : ""
            color: Theme.dim
            font.pixelSize: 14
        }
    }
    readonly property int who: of ? of.id : -1
    onWhoChanged: if (who >= 0) wave.restart()
    Row {
        id: pills
        anchors { bottom: parent.bottom; bottomMargin: 34; horizontalCenter: parent.horizontalCenter }
        height: 42
        spacing: 10
        Pill { visible: m.of !== null; text: m.code === "" ? Tr.t("Later") : Tr.t("Conversation"); onClicked: m.code === "" ? m.later() : m.reply() }
        Pill { visible: m.of !== null; filled: true; text: m.code === "" ? Tr.t("Reply") : Tr.t("Copy code"); onClicked: m.code === "" ? m.reply() : m.copy(m.code) }
    }
}
