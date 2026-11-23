// SPDX-License-Identifier: GPL-3.0-or-later
import QtQuick
import QtQuick.Shapes
import dev.pairlume

// Everyone, those who wait, or those that are searched for.
Card {
    id: c
    required property Texts texts
    // no other card says what is wrong
    property bool alone: true
    property string show: "all"       // all | new | search
    property alias list: list
    readonly property bool searching: show === "search"
    function search() { show = "search"; find.forceActiveFocus() }
    function shut() { if (!searching) return false; find.text = ""; show = "all"; return true }
    signal chosen(var thread)
    title: Tr.t("Messages")
    side: 84
    line: texts.trouble !== "" && texts.threads.count > 0 ? texts.trouble.split("\n")[0]
        : texts.waiting > 0 ? Tr.t("Waiting for you: %1").arg(texts.waiting) : texts.threads.count > 0 ? Tr.t("Nobody is waiting") : ""
    lineColor: texts.trouble !== "" && texts.threads.count > 0 ? Theme.bad : Theme.dim
    // the settings: language, and what comes later
    Item {
        x: 22
        y: 30
        width: 44
        height: 44
        activeFocusOnTab: true
        Accessible.role: Accessible.Button
        Accessible.name: Tr.t("Settings")
        Keys.onReturnPressed: c.texts.service.open(JSON.stringify(["settings"]))
        Rectangle { anchors.fill: parent; radius: 22; color: Theme.fade(Theme.text, gm.containsMouse ? 0.14 : 0.07); border { width: parent.activeFocus ? 2 : 0; color: Theme.text } }
        Shape { anchors.centerIn: parent; width: 24; height: 24; preferredRendererType: Shape.CurveRenderer
            ShapePath { strokeWidth: 2; strokeColor: Theme.text; fillColor: "transparent"; capStyle: ShapePath.RoundCap; joinStyle: ShapePath.RoundJoin
                PathSvg { path: "M12 15.5a3.5 3.5 0 1 0 0-7 3.5 3.5 0 0 0 0 7zM19.4 15a1.7 1.7 0 0 0 .3 1.8l.1.1a2 2 0 1 1-2.8 2.8l-.1-.1a1.7 1.7 0 0 0-1.8-.3 1.7 1.7 0 0 0-1 1.5V21a2 2 0 1 1-4 0v-.1a1.7 1.7 0 0 0-1.1-1.5 1.7 1.7 0 0 0-1.8.3l-.1.1a2 2 0 1 1-2.8-2.8l.1-.1a1.7 1.7 0 0 0 .3-1.8 1.7 1.7 0 0 0-1.5-1H3a2 2 0 1 1 0-4h.1a1.7 1.7 0 0 0 1.5-1.1 1.7 1.7 0 0 0-.3-1.8l-.1-.1a2 2 0 1 1 2.8-2.8l.1.1a1.7 1.7 0 0 0 1.8.3H9a1.7 1.7 0 0 0 1-1.5V3a2 2 0 1 1 4 0v.1a1.7 1.7 0 0 0 1 1.5 1.7 1.7 0 0 0 1.8-.3l.1-.1a2 2 0 1 1 2.8 2.8l-.1.1a1.7 1.7 0 0 0-.3 1.8V9a1.7 1.7 0 0 0 1.5 1H21a2 2 0 1 1 0 4h-.1a1.7 1.7 0 0 0-1.5 1z" } } }
        MouseArea { id: gm; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: c.texts.service.open(JSON.stringify(["settings"])) }
    }
    ThreadList {
        id: list
        anchors { fill: parent; leftMargin: 14; rightMargin: 14; topMargin: c.below + 6; bottomMargin: 92 }
        texts: c.texts
        find: find.text
        fresh: c.show === "new"
        onChosen: t => c.chosen(t)
    }
    // the last row fades under the buttons
    Rectangle {
        anchors { left: parent.left; right: parent.right; leftMargin: 2; rightMargin: 2; bottom: list.bottom }
        height: 44
        visible: !list.atYEnd
        gradient: Gradient {
            GradientStop { position: 0; color: Theme.fade(Theme.surface, 0) }
            GradientStop { position: 1; color: Theme.surface }
        }
    }
    Text {
        anchors.centerIn: parent
        width: parent.width - 72
        horizontalAlignment: Text.AlignHCenter
        wrapMode: Text.Wrap
        textFormat: Text.PlainText
        text: c.texts.threads.count === 0 ? (c.texts.loading ? Tr.t("Asking the phone") : c.texts.trouble !== "" ? (c.alone ? c.texts.trouble : "") : Tr.t("No messages"))
            : list.hits > 0 ? "" : c.searching ? Tr.t("Nothing found") : Tr.t("Nobody is waiting")
        color: Theme.dim
        font.pixelSize: 14
    }
    Row {
        anchors { bottom: parent.bottom; bottomMargin: 34; horizontalCenter: parent.horizontalCenter }
        spacing: 10
        visible: !c.searching && c.texts.threads.count > 0
        Pill { text: Tr.t("All"); chosen: c.show === "all"; onClicked: c.show = "all" }
        Pill { text: Tr.t("New"); chosen: c.show === "new"; onClicked: c.show = "new" }
        Pill { text: Tr.t("Search"); onClicked: c.search() }
    }
    Row {
        anchors { bottom: parent.bottom; bottomMargin: 34; horizontalCenter: parent.horizontalCenter }
        spacing: 10
        visible: c.searching
        Rectangle {
            width: c.width - 58 - shut.width
            height: 42
            radius: 21
            color: Theme.fade(Theme.text, 0.07)
            border { width: find.activeFocus ? 2 : 0; color: Theme.accent }
            TextInput {
                id: find
                anchors { fill: parent; leftMargin: 18; rightMargin: 18 }
                verticalAlignment: TextInput.AlignVCenter
                color: Theme.text
                selectionColor: Theme.accent
                selectedTextColor: Theme.ink
                font.pixelSize: 14
                clip: true
                Accessible.name: Tr.t("Search")
                onAccepted: list.pickNth(0)
                Keys.onDownPressed: list.step(1)
                Keys.onUpPressed: list.step(-1)
                Keys.onEscapePressed: c.shut()
                Text { visible: find.text === "" && find.preeditText === ""; anchors.verticalCenter: parent.verticalCenter; text: Tr.t("Name, number or word"); color: Theme.dim; font: find.font }
            }
        }
        Pill { id: shut; text: Tr.t("Close"); onClicked: c.shut() }
    }
}
