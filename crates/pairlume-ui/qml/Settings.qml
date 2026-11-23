// SPDX-License-Identifier: GPL-3.0-or-later
import QtQuick
import QtQuick.Window
import dev.pairlume

// pairlume-ui settings: what the windows look like and speak. For now: the language.
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

    Item {
        id: scene
        anchors.fill: parent
        Card {
            id: card
            anchors { fill: parent; margins: 12 }
            solid: true
            title: Tr.t("Settings")
            line: Tr.t("Language")
            ListView {
                id: list
                anchors { fill: parent; leftMargin: 14; rightMargin: 14; topMargin: card.below + 6; bottomMargin: 92 }
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
            Text {
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
    Shots { of: scene; what: langs.length > 0 ? "settings-" + Tr.lang : "" }
}
