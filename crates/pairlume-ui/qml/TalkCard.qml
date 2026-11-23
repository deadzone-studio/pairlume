// SPDX-License-Identifier: GPL-3.0-or-later
import QtQuick
import QtQuick.Shapes
import dev.pairlume

// A conversation.
Card {
    id: c
    required property Texts texts
    property bool back: true
    readonly property string code: { texts.messages.count; return texts.lastCode() }
    function copyCode() { if (code !== "") copy(code) }
    signal left_
    signal copy(string text)
    side: 84
    title: texts.head ? texts.title(texts.head) : ""
    line: texts.head && texts.head.name !== "" ? texts.head.address : ""
    lineClickable: true
    onLineClicked: copy(line)
    Item {
        visible: c.back
        x: 22
        y: 30
        width: 44
        height: 44
        activeFocusOnTab: true
        Accessible.role: Accessible.Button
        Accessible.name: Tr.t("Back")
        Keys.onReturnPressed: c.left_()
        Rectangle { anchors.fill: parent; radius: 22; color: Theme.fade(Theme.text, bm.containsMouse ? 0.14 : 0.07); border { width: parent.activeFocus ? 2 : 0; color: Theme.text } }
        Shape { anchors.centerIn: parent; width: 24; height: 24; preferredRendererType: Shape.CurveRenderer
            ShapePath { strokeWidth: 2.4; strokeColor: Theme.text; fillColor: "transparent"; capStyle: ShapePath.RoundCap; joinStyle: ShapePath.RoundJoin; PathSvg { path: "M15 5l-7 7 7 7" } } }
        MouseArea { id: bm; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: c.left_() }
    }
    Avatar { anchors { right: parent.right; rightMargin: 22 } y: 27; width: 50; name: c.title; address: c.texts.head ? c.texts.head.address : ""; photo: c.texts.head ? c.texts.face(c.texts.head.address) : "" }
    Talk { anchors { left: parent.left; right: parent.right; top: parent.top; bottom: take.visible ? take.top : line.top; leftMargin: 24; rightMargin: 24; topMargin: c.below; bottomMargin: 12 } texts: c.texts }
    Pill { id: take; visible: c.code !== ""; anchors { bottom: line.top; bottomMargin: 12; horizontalCenter: parent.horizontalCenter } text: Tr.t("Copy %1").arg(c.code); onClicked: c.copyCode() }
    Composer { id: line; anchors { bottom: parent.bottom; bottomMargin: 34; horizontalCenter: parent.horizontalCenter } width: Math.min(parent.width - 48, 760); height: implicitHeight; texts: c.texts }
}
