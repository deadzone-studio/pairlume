// SPDX-License-Identifier: GPL-3.0-or-later
import QtQuick
import QtQuick.Window
import dev.pairlume

Window {
    id: win
    title: Tr.t("Messages")
    width: 980
    height: 680
    minimumWidth: 360
    minimumHeight: 420
    color: "transparent"
    visible: true
    Service { id: service; onBlurredChanged: Theme.blurred = blurred; onColorsChanged: { try { Theme.from = JSON.parse(colors) } catch (e) { console.warn("colors: " + e) } } }
    Texts { id: texts; service: service }
    // --backdrop FILE: a picture behind it, as if it was the blurred wallpaper (for the README)
    Item {
        id: scene
        anchors.fill: parent
    Image { anchors.fill: parent; fillMode: Image.PreserveAspectCrop; source: { const a = Qt.application.arguments, i = a.indexOf("--backdrop"); return i > 0 ? "file://" + a[i + 1] : "" } visible: source != "" }
    // the compositor rounds the window
    MessagesView { id: view; radius: 0; anchors.fill: parent; texts: texts; focus: true; Keys.onEscapePressed: texts.leave() }
    }
    Shots { of: scene; what: texts.open >= 0 ? "messages-" + texts.open + "-" + texts.messages.count : texts.threads.count > 0 ? "messages" : "" }
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
