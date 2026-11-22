// SPDX-License-Identifier: GPL-3.0-or-later
import QtQuick
import QtQuick.Window
import dev.pairlume

Window {
    id: win
    title: qsTr("Messages")
    width: 920
    height: 640
    minimumWidth: 360
    minimumHeight: 420
    color: "transparent"
    visible: true
    Service { id: service; onColorsChanged: { try { Theme.from = JSON.parse(colors) } catch (e) { console.warn("colors.json: " + e) } } }
    Texts { id: texts; service: service }
    MessagesView { id: view; anchors.fill: parent; texts: texts; focus: true; Keys.onEscapePressed: texts.leave() }
    Shots { of: view; what: texts.open >= 0 ? "messages-" + texts.open + "-" + texts.messages.count : texts.threads.count > 0 ? "messages" : "" }
    // --open N: the Nth conversation at once
    Connections {
        target: texts
        function onLoadingChanged() {
            const i = Qt.application.arguments.indexOf("--open")
            if (i > 0 && !texts.loading && texts.open < 0 && texts.threads.count > 0) {
                const t = texts.threads.get(parseInt(Qt.application.arguments[i + 1]) || 0)
                if (t) texts.show({ id: t.id, name: t.name, address: t.address })
            }
        }
    }
}
