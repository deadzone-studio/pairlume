// SPDX-License-Identifier: GPL-3.0-or-later
import QtQuick
import QtQuick.Window
import dev.pairlume

// pairlume-ui settings: what the windows speak and how the phone's notifications look. Every window follows a choice
// at once.
Window {
    id: win
    title: Tr.t("Settings")
    width: 480
    height: 720
    minimumWidth: 360
    minimumHeight: 480
    color: Theme.ground
    visible: false
    Service { id: service; onBlurredChanged: Theme.blurred = blurred; onColorsChanged: { try { Theme.from = JSON.parse(colors) } catch (e) { } } }
    Component.onCompleted: {
        if (Qt.application.arguments.indexOf("--shots") < 0 && !service.claim("settings", "[]")) { Qt.callLater(Qt.quit); return }
        visible = true
        service.start()
    }
    Connections { target: service; function onAgain(args) { service.front() } }
    readonly property var langs: { try { return JSON.parse(service.languages()) } catch (e) { return [] } }
    property string chosen: service.chosenLanguage()
    // the system's language, when there is a file for it
    readonly property string system: { const c = Qt.locale().name.slice(0, 2); return langs.some(l => l[0] === c) ? c : "en" }
    function nameOf(code) { const l = langs.find(x => x[0] === code); return l ? l[1] : code }
    function pick(code) { service.chooseLanguage(code); chosen = code; Tr.chosen = code }
    // language | notifications; --page notifications for pictures
    property string page: { const a = Qt.application.arguments, i = a.indexOf("--page"); return i > 0 ? a[i + 1] : "language" }
    function look(style) { service.setUiValue("notif_style", style); Tr.notifStyle = style }
    Texts { id: sample; service: service }
    // what a notification looks like, for the preview: made up, the same as in the pictures
    readonly property var example: ({ key: "example", app: "", appName: "Messages", title: "Emma", text: Tr.t("Are you coming tonight? Bring the charger, mine is dead."),
                                      when: Date.now() - 120000, actions: JSON.stringify([{ title: Tr.t("Reply"), reply: true }, { title: Tr.t("Mark as read") }]),
                                      pMax: 0, pValue: 0, pBusy: false })

    Item {
        id: scene
        anchors.fill: parent
        Card {
            id: card
            anchors { fill: parent; margins: 12 }
            solid: true
            title: Tr.t("Settings")
            line: ""
            // the two pages
            Row {
                id: tabs
                anchors { horizontalCenter: parent.horizontalCenter; top: parent.top; topMargin: card.below - 30 }
                spacing: 8
                Pill { text: Tr.t("Language"); filled: win.page === "language"; onClicked: win.page = "language" }
                Pill { text: Tr.t("Notifications"); filled: win.page === "notifications"; onClicked: win.page = "notifications" }
            }
            ListView {
                id: list
                visible: win.page === "language"
                anchors { fill: parent; leftMargin: 14; rightMargin: 14; topMargin: card.below + 22; bottomMargin: 92 }
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                model: [""].concat(win.langs.map(l => l[0]))
                delegate: Item {
                    id: row
                    required property string modelData
                    readonly property bool on: win.chosen === modelData
                    width: list.width
                    height: 54
                    Accessible.role: Accessible.RadioButton
                    Accessible.name: label.text
                    Accessible.checked: on
                    Rectangle { anchors { fill: parent; topMargin: 2; bottomMargin: 2 } radius: 22; color: row.on ? Theme.fade(Theme.accent, 0.18) : Theme.fade(Theme.text, m.containsMouse ? 0.06 : 0) }
                    // the ring of the pairing phone around the chosen one
                    Rectangle {
                        x: 14; anchors.verticalCenter: parent.verticalCenter
                        width: 22; height: 22; radius: 11
                        color: "transparent"
                        border { width: 2; color: row.on ? Theme.accent : Theme.fade(Theme.text, 0.35) }
                        Rectangle { anchors.centerIn: parent; width: 10; height: 10; radius: 5; color: Theme.accent; visible: row.on }
                    }
                    Text {
                        id: label
                        x: 50; anchors.verticalCenter: parent.verticalCenter
                        width: parent.width - 64
                        elide: Text.ElideRight
                        textFormat: Text.PlainText
                        text: row.modelData === "" ? Tr.t("As the system (%1)").arg(win.nameOf(win.system)) : win.nameOf(row.modelData)
                        color: Theme.text
                        font { pixelSize: 15; weight: row.on ? Font.DemiBold : Font.Normal }
                    }
                    MouseArea { id: m; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: win.pick(row.modelData) }
                }
            }
            // ---------- notifications ----------
            Column {
                visible: win.page === "notifications"
                anchors { left: parent.left; right: parent.right; top: parent.top; topMargin: card.below + 22; leftMargin: 14; rightMargin: 14 }
                spacing: 2
                Repeater {
                    model: [["card", Tr.t("Cards"), Tr.t("At the top right, with their buttons")],
                            ["banner", Tr.t("Like texts on an iPhone"), Tr.t("A banner at the top; a click opens the conversation")],
                            ["system", Tr.t("As the system's"), Tr.t("Your desktop shows them like all its notifications")]]
                    delegate: Item {
                        id: st
                        required property var modelData
                        readonly property bool on: Tr.notifStyle === modelData[0]
                        width: parent.width
                        height: 64
                        Accessible.role: Accessible.RadioButton
                        Accessible.name: modelData[1]
                        Accessible.checked: on
                        Rectangle { anchors { fill: parent; topMargin: 2; bottomMargin: 2 } radius: 22; color: st.on ? Theme.fade(Theme.accent, 0.18) : Theme.fade(Theme.text, sm.containsMouse ? 0.06 : 0) }
                        Rectangle {
                            x: 14; anchors.verticalCenter: parent.verticalCenter
                            width: 22; height: 22; radius: 11
                            color: "transparent"
                            border { width: 2; color: st.on ? Theme.accent : Theme.fade(Theme.text, 0.35) }
                            Rectangle { anchors.centerIn: parent; width: 10; height: 10; radius: 5; color: Theme.accent; visible: st.on }
                        }
                        Column {
                            x: 50; anchors.verticalCenter: parent.verticalCenter
                            width: parent.width - 64
                            Text { width: parent.width; text: st.modelData[1]; textFormat: Text.PlainText; elide: Text.ElideRight; color: Theme.text; font { pixelSize: 15; weight: st.on ? Font.DemiBold : Font.Normal } }
                            Text { width: parent.width; text: st.modelData[2]; textFormat: Text.PlainText; elide: Text.ElideRight; color: Theme.dim; font.pixelSize: 12 }
                        }
                        MouseArea { id: sm; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: win.look(st.modelData[0]) }
                    }
                }
                Item { width: 1; height: 18 }
                // how it looks, with your colors
                // the system's look is the desktop's own: no picture of it here, a real one to try
                Column {
                    visible: Tr.notifStyle === "system"
                    width: parent.width
                    spacing: 12
                    Text { width: parent.width; wrapMode: Text.Wrap; textFormat: Text.PlainText; horizontalAlignment: Text.AlignHCenter; color: Theme.dim; font.pixelSize: 13
                           text: Tr.t("They look the way your desktop draws notifications. An answer opens a small Pairlume window.") }
                    Pill {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: Tr.t("Show one to try")
                        onClicked: service.sysShow(JSON.stringify({ key: "pairlume-example", app: "", app_name: "Pairlume", title: win.example.title, text: win.example.text,
                                                                     actions: [["dismiss", Tr.t("Dismiss")]] }))
                    }
                }
                Item {
                    visible: Tr.notifStyle !== "system"
                    width: parent.width
                    height: (Tr.notifStyle === "banner" ? pb.height : pc.height) * 0.92
                    // only to look at: clicks stop here
                    NotifCard { id: pc; visible: Tr.notifStyle !== "banner"; anchors.horizontalCenter: parent.horizontalCenter; scale: 0.92; transformOrigin: Item.Top; texts: sample; model: win.example }
                    NotifBanner { id: pb; visible: Tr.notifStyle === "banner"; anchors.horizontalCenter: parent.horizontalCenter; scale: 0.92; transformOrigin: Item.Top; texts: sample; model: win.example }
                    MouseArea { anchors.fill: parent; hoverEnabled: true }
                }
            }
            Text {
                visible: win.page === "language"
                anchors { left: parent.left; right: parent.right; bottom: parent.bottom; margins: 26; bottomMargin: 34 }
                wrapMode: Text.Wrap
                horizontalAlignment: Text.AlignHCenter
                textFormat: Text.PlainText
                text: Tr.t("Translations are made by people who use Pairlume. Found a mistake? Tell us on GitHub.")
                color: Theme.dim
                font.pixelSize: 13
            }
        }
    }
    Shots { of: scene; what: langs.length > 0 ? "settings-" + (win.page === "language" ? Tr.lang : win.page + "-" + Tr.notifStyle) : "" }
}
