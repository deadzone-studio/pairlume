// SPDX-License-Identifier: GPL-3.0-or-later
import QtQuick
import dev.pairlume

// A call, like a step of pairing: who it is, what the call is doing, what to do.
Card {
    id: k
    required property Texts texts
    readonly property var c: texts.call
    readonly property string st: c ? c.state : ""
    readonly property string who: c ? (c.name || c.number || Tr.t("Hidden number")) : ""
    property real now: Date.now()
    signal close
    signal write(var thread)
    Timer { interval: 1000; repeat: true; running: k.st === "talking"; onTriggered: k.now = Date.now() }
    function clock(ms) { const s = Math.max(0, Math.floor(ms / 1000)); return Math.floor(s / 60) + ":" + String(s % 60).padStart(2, "0") }
    title: who
    line: st === "ringing" ? Tr.t("is calling") : st === "dialing" ? Tr.t("calling") : st === "talking" ? Tr.t("on the phone, %1").arg(clock(now - c.since))
        : c && c.missed ? Tr.t("missed call, %1").arg(Qt.formatTime(new Date(c.since), "HH:mm")) : Tr.t("call ended")
    lineColor: c && c.missed ? Theme.bad : Theme.dim
    Item {
        id: stage
        anchors { left: parent.left; right: parent.right; top: parent.top; topMargin: k.below; bottom: pills.top }
        Rings { anchors.centerIn: parent; width: Math.min(280, stage.height); height: width; on: k.st === "ringing" || k.st === "dialing"; visible: on }
        Avatar {
            anchors.centerIn: parent
            width: 112
            ring: k.st !== "ended"
            name: k.c ? k.c.name : ""
            address: k.c ? k.c.number : ""
            photo: k.c ? (k.c.png || k.texts.face(k.c.number)) : ""
            Accessible.ignored: true
        }
        Text {
            anchors { horizontalCenter: parent.horizontalCenter; bottom: parent.bottom; bottomMargin: 18 }
            width: parent.width - 60
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.Wrap
            textFormat: Text.PlainText
            text: k.texts.callTrouble !== "" ? k.texts.callTrouble : k.c && k.c.name !== "" ? k.c.number : k.st === "talking" ? Tr.t("The voice stays on the phone") : ""
            color: k.texts.callTrouble !== "" ? Theme.bad : Theme.dim
            font.pixelSize: 14
        }
    }
    onStChanged: texts.callTrouble = ""
    Row {
        id: pills
        anchors { bottom: parent.bottom; bottomMargin: 34; horizontalCenter: parent.horizontalCenter }
        height: 42
        spacing: 10
        Pill { visible: k.st === "ringing"; text: Tr.t("Decline"); onClicked: k.texts.callDo("end") }
        Pill { visible: k.st === "ringing"; filled: true; text: Tr.t("Answer"); onClicked: k.texts.callDo("answer") }
        Pill { visible: k.st === "talking" || k.st === "dialing"; filled: true; text: Tr.t("End call"); onClicked: k.texts.callDo("end") }
        Pill { visible: k.st === "ended"; text: Tr.t("Close"); onClicked: k.close() }
        Pill { visible: k.st === "ended" && k.c.number !== ""; text: Tr.t("Text"); onClicked: k.write({ id: -1, name: k.c.name, address: k.c.number }) }
        Pill { visible: k.st === "ended" && k.c.number !== ""; filled: true; text: Tr.t("Call back"); onClicked: k.texts.callDo("dial", k.c.number) }
    }
}
