// SPDX-License-Identifier: GPL-3.0-or-later
import QtQuick
import dev.pairlume

// The list and the conversation: side by side when there is room, else one over the other.
Item {
    id: v
    required property Texts texts
    property real radius: 30
    readonly property bool wide: width >= 640
    readonly property bool talking: texts.open >= 0
    Rectangle {
        anchors.fill: parent
        radius: v.radius
        color: Theme.fade(Theme.surface, Theme.glass)
        border { width: v.radius > 0 ? 1 : 0; color: Theme.fade(Theme.text, 0.14) }
        // a breath of the accent color, as if something shone in
        Rectangle {
            anchors { fill: parent; margins: 1 }
            radius: Math.max(0, v.radius - 1)
            gradient: Gradient {
                orientation: Gradient.Horizontal
                GradientStop { position: 0; color: Theme.fade(Theme.accent, 0.1) }
                GradientStop { position: 0.6; color: Theme.fade(Theme.accent2, 0.04) }
                GradientStop { position: 1; color: Theme.fade(Theme.accent2, 0) }
            }
        }
    }
    Item {
        id: side
        x: !v.wide && v.talking ? -width * 0.3 : v.wide ? 12 : 0
        y: v.wide ? 12 : 0
        width: v.wide ? 316 : v.width
        height: v.height - 2 * y
        opacity: !v.wide && v.talking ? 0 : 1
        visible: opacity > 0
        Behavior on x { NumberAnimation { duration: Theme.normal; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.smooth } }
        Behavior on opacity { NumberAnimation { duration: Theme.quick } }
        Glass { anchors.fill: parent; radius: 24; lift: 0.05; visible: v.wide }
        Text { id: t; x: 22; y: 18; text: Tr.t("Messages"); color: Theme.text; font.pixelSize: 27; font.weight: Font.Bold; font.letterSpacing: -0.4 }
        Row {
            anchors { right: parent.right; rightMargin: 20; verticalCenter: t.verticalCenter }
            spacing: 7
            Rectangle { width: 8; height: 8; radius: 4; anchors.verticalCenter: parent.verticalCenter; color: v.texts.online ? "#5bd48a" : Theme.dim }
            Text { width: Math.min(implicitWidth, side.width - t.width - 80); elide: Text.ElideRight; textFormat: Text.PlainText; text: v.texts.deviceName; color: Theme.dim; font.pixelSize: 12 }
        }
        Glass {
            id: search
            anchors { left: parent.left; right: parent.right; leftMargin: 14; rightMargin: 14; top: t.bottom; topMargin: 12 }
            height: 40
            radius: 20
            lift: f.activeFocus ? 0.12 : 0.07
            TextInput {
                id: f
                anchors { fill: parent; leftMargin: 18; rightMargin: 18 }
                verticalAlignment: TextInput.AlignVCenter
                color: Theme.text
                selectionColor: Theme.accent
                selectedTextColor: Theme.ink
                font.pixelSize: 14
                clip: true
                Accessible.name: Tr.t("Search")
                Keys.onEscapePressed: e => { if (text !== "") text = ""; else e.accepted = false }
                Text { visible: f.text === "" && f.preeditText === ""; anchors.verticalCenter: parent.verticalCenter; text: Tr.t("Search"); color: Theme.dim; font: f.font }
            }
        }
        ThreadList {
            id: list
            anchors { left: parent.left; right: parent.right; top: search.bottom; bottom: parent.bottom; leftMargin: 8; rightMargin: 8; topMargin: 10; bottomMargin: 8 }
            texts: v.texts
            find: f.text
            onChosen: thread => v.texts.show(thread)
        }
        Text {
            anchors.centerIn: parent
            width: parent.width - 60
            visible: text !== ""
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.Wrap
            textFormat: Text.PlainText
            text: v.texts.threads.count === 0 ? (v.texts.trouble !== "" ? v.texts.trouble : v.texts.loading ? Tr.t("Asking the phone") : Tr.t("No messages")) : list.some ? "" : Tr.t("Nothing found")
            color: Theme.dim
            font.pixelSize: 14
        }
    }
    Talk {
        texts: v.texts
        back: !v.wide
        readonly property real left0: v.wide ? 340 : 0
        width: v.width - left0
        height: v.height
        x: v.wide ? left0 : v.talking ? 0 : v.width * 0.4
        opacity: v.wide || v.talking ? 1 : 0
        visible: opacity > 0
        enabled: v.wide || v.talking
        Behavior on x { enabled: !v.wide; NumberAnimation { duration: Theme.normal; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.smooth } }
        Behavior on opacity { NumberAnimation { duration: Theme.quick } }
        onGoBack: v.texts.leave()
    }
}
