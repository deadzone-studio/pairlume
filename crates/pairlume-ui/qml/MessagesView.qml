// SPDX-License-Identifier: GPL-3.0-or-later
import QtQuick
import dev.pairlume

// The list and the conversation: side by side when there is room, else one over the other.
Item {
    id: v
    required property Texts texts
    readonly property bool wide: width >= 640
    readonly property bool talking: texts.open >= 0
    Rectangle {
        anchors.fill: parent
        radius: 28
        color: Theme.fade(Theme.surface, Theme.glass)
        border.color: Theme.fade(Theme.text, 0.12)
    }
    Item {
        id: side
        width: v.wide ? 300 : v.width
        height: v.height
        x: !v.wide && v.talking ? -width * 0.3 : 0
        opacity: !v.wide && v.talking ? 0 : 1
        visible: opacity > 0
        Behavior on x { NumberAnimation { duration: Theme.normal; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.smooth } }
        Behavior on opacity { NumberAnimation { duration: Theme.quick } }
        Text { id: t; x: 24; y: 22; text: qsTr("Messages"); color: Theme.text; font.pixelSize: 24; font.weight: Font.Bold }
        Text { anchors { left: t.left; top: t.bottom; topMargin: 2 } width: side.width - 48; elide: Text.ElideRight; textFormat: Text.PlainText; text: v.texts.deviceName; color: Theme.dim; font.pixelSize: 12 }
        ThreadList {
            anchors { fill: parent; topMargin: 84; leftMargin: 10; rightMargin: 10; bottomMargin: 12 }
            texts: v.texts
            onChosen: thread => v.texts.show(thread)
        }
        Text {
            anchors.centerIn: parent
            width: parent.width - 60
            visible: text !== ""
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.Wrap
            textFormat: Text.PlainText
            text: v.texts.trouble !== "" && v.texts.threads.count === 0 ? v.texts.trouble : v.texts.loading ? qsTr("Asking the phone") : v.texts.online && v.texts.threads.count === 0 ? qsTr("No messages") : ""
            color: Theme.dim
            font.pixelSize: 14
        }
    }
    Rectangle { visible: v.wide; x: 300; width: 1; height: v.height; color: Theme.fade(Theme.text, 0.08) }
    Talk {
        texts: v.texts
        back: !v.wide
        width: v.wide ? v.width - 301 : v.width
        height: v.height
        x: v.wide ? 301 : v.talking ? 0 : v.width * 0.4
        opacity: v.wide || v.talking ? 1 : 0
        visible: opacity > 0
        enabled: v.wide || v.talking
        Behavior on x { enabled: !v.wide; NumberAnimation { duration: Theme.normal; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.smooth } }
        Behavior on opacity { NumberAnimation { duration: Theme.quick } }
        onGoBack: v.texts.leave()
    }
}
