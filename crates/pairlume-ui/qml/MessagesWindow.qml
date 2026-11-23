// SPDX-License-Identifier: GPL-3.0-or-later
import QtQuick
import QtQuick.Window
import dev.pairlume

Window {
    id: win
    title: Tr.t("Messages")
    width: 1000
    height: 680
    minimumWidth: 360
    minimumHeight: 420
    color: Theme.ground
    visible: true
    Service { id: service; onBlurredChanged: Theme.blurred = blurred; onColorsChanged: { try { Theme.from = JSON.parse(colors) } catch (e) { console.warn("colors: " + e) } } }
    Texts { id: texts; service: service }
    Item {
        id: scene
        anchors.fill: parent
        Rectangle { anchors.fill: parent; color: Theme.ground }
        MessagesView { id: view; anchors { fill: parent; margins: 12 } texts: texts; solid: true; focus: true }
    }
    Shots { of: scene; what: texts.call ? "call-" + texts.call.state : texts.open >= 0 ? "messages-" + texts.open + "-" + texts.messages.count : texts.threads.count > 0 ? "messages" : texts.trouble !== "" ? "messages-off" : "" }
    // --open N: the Nth conversation at once; --size WxH
    Component.onCompleted: {
        const a = Qt.application.arguments, i = a.indexOf("--size")
        if (i > 0) { width = parseInt(a[i + 1]); height = parseInt(a[i + 1].split("x")[1]) }
    }
    Connections {
        target: texts
        function onLoadingChanged() {
            // --to NUMBER: the conversation with that number (from a call)
            const a = Qt.application.arguments, to = a.indexOf("--to")
            if (to > 0 && !texts.loading && texts.open < 0 && texts.threads.count > 0) {
                const want = (a[to + 1] || "").replace(/[^0-9]/g, "").slice(-9)
                for (let k = 0; k < texts.threads.count; k++) {
                    const t = texts.threads.get(k)
                    if (want.length >= 3 && t.address.replace(/[^0-9]/g, "").endsWith(want)) { texts.show({ id: t.id, name: t.name, address: t.address }); return }
                }
            }
            const i = Qt.application.arguments.indexOf("--open")
            if (i > 0 && !texts.loading && texts.open < 0 && texts.threads.count > 0) {
                const t = texts.threads.get(parseInt(Qt.application.arguments[i + 1]) || 0)
                if (t) texts.show({ id: t.id, name: t.name, address: t.address })
            }
        }
    }
}
