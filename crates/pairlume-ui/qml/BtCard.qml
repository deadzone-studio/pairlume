// SPDX-License-Identifier: GPL-3.0-or-later
import QtQuick
import dev.pairlume

// The phone pairs over Bluetooth, for the voice of calls: the same question as when pairing.
Card {
    id: b
    required property Texts texts
    readonly property var bt: texts.bt
    readonly property bool asking: bt !== null && bt.code !== undefined
    property bool answered: false
    onBtChanged: answered = false
    signal close
    title: bt ? bt.name : ""
    line: asking ? Tr.t("Bluetooth for calls: is the same code on the phone?") : bt && bt.ok ? Tr.t("Calls can be heard here now") : Tr.t("Bluetooth was not paired")
    lineColor: bt && bt.ok === false ? Theme.bad : Theme.dim
    Item {
        anchors { left: parent.left; right: parent.right; top: parent.top; topMargin: b.below; bottom: pills.top }
        Phone { anchors { horizontalCenter: parent.horizontalCenter; bottom: digits.top; bottomMargin: 34 } glow: 1; visible: b.asking }
        Loader { id: digits; anchors.centerIn: parent; active: b.asking; sourceComponent: Digits { code: b.bt.code } }
        Avatar { anchors.centerIn: parent; width: 112; ring: true; visible: !b.asking; name: b.bt ? b.bt.name : "" }
    }
    Row {
        id: pills
        anchors { bottom: parent.bottom; bottomMargin: 34; horizontalCenter: parent.horizontalCenter }
        height: 42
        spacing: 12
        Pill { visible: b.asking; text: Tr.t("Not the same"); enabled: !b.answered; onClicked: { b.answered = true; b.texts.btAnswer(false) } }
        Pill { visible: b.asking; filled: true; text: Tr.t("They match"); enabled: !b.answered; onClicked: { b.answered = true; b.texts.btAnswer(true) } }
        Pill { visible: !b.asking; text: Tr.t("Close"); onClicked: b.close() }
    }
}
