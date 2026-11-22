// SPDX-License-Identifier: GPL-3.0-or-later
import QtQuick
import QtQuick.Window
import org.kde.layershell as LayerShell
import dev.pairlume

// Round faces at the edge of the screen. A new text brings its face; a click opens the conversation beside it.
Window {
    id: win
    readonly property bool wide: texts.open >= 0 || closing.running
    LayerShell.Window.scope: "pairlume"
    LayerShell.Window.layer: LayerShell.Window.LayerTop
    LayerShell.Window.anchors: LayerShell.Window.AnchorRight
    LayerShell.Window.keyboardInteractivity: texts.open >= 0 ? LayerShell.Window.KeyboardInteractivityOnDemand : LayerShell.Window.KeyboardInteractivityNone
    LayerShell.Window.exclusionZone: 0
    title: qsTr("Messages")
    width: wide ? 460 : 76
    height: 560
    color: "transparent"
    visible: true
    Service { id: service; onColorsChanged: { try { Theme.from = JSON.parse(colors) } catch (e) { console.warn("colors.json: " + e) } } }
    Texts {
        id: texts
        service: service
        onCame: (thread, message) => win.face(thread, true)
        onLoadingChanged: if (!loading && faces.count === 0) for (let i = 0; i < Math.min(3, threads.count); i++) { const t = threads.get(i); win.face({ id: t.id, name: t.name, address: t.address, unread: t.unread }, false, true) }
    }
    ListModel { id: faces }
    Connections {
        target: texts
        function onOpenChanged() { for (let i = 0; i < faces.count; i++) if (faces.get(i).tid === texts.open) faces.setProperty(i, "unread", 0) }
    }
    Timer { id: closing; interval: Theme.normal }
    function face(t, first, last) {
        for (let i = 0; i < faces.count; i++) if (faces.get(i).tid === t.id) {
            faces.setProperty(i, "unread", t.id === texts.open ? 0 : t.unread)
            if (first && i > 0) faces.move(i, 0, 1)
            return
        }
        const f = { tid: t.id, name: t.name, address: t.address, unread: t.id === texts.open ? 0 : t.unread }
        if (last) faces.append(f); else faces.insert(0, f)
        while (faces.count > 6) faces.remove(faces.count - 1)
    }
    Item {
        id: scene
        anchors.fill: parent
        focus: true
        Keys.onEscapePressed: { closing.start(); texts.leave() }
        Rectangle {
            id: card
            readonly property bool on: texts.open >= 0
            x: 8
            width: 374
            height: parent.height
            radius: 28
            color: Theme.fade(Theme.surface, Theme.glass)
            border.color: Theme.fade(Theme.text, 0.12)
            transformOrigin: Item.Right
            scale: on ? 1 : 0.6
            opacity: on ? 1 : 0
            visible: opacity > 0
            Behavior on scale { NumberAnimation { duration: Theme.normal; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.spring } }
            Behavior on opacity { NumberAnimation { duration: Theme.quick } }
            Talk { anchors.fill: parent; texts: texts; back: false }
        }
        ListView {
            id: dock
            anchors { right: parent.right; rightMargin: 10; verticalCenter: parent.verticalCenter }
            width: 60
            height: Math.min(parent.height, contentHeight)
            spacing: 10
            interactive: false
            model: faces
            add: Transition { NumberAnimation { property: "scale"; from: 0; to: 1; duration: Theme.slow; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.spring } }
            remove: Transition { NumberAnimation { property: "scale"; to: 0; duration: Theme.quick } }
            displaced: Transition { NumberAnimation { property: "y"; duration: Theme.normal; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.smooth } }
            move: displaced
            delegate: Item {
                id: f
                required property var model
                width: 60
                height: 60
                Avatar {
                    anchors.centerIn: parent
                    width: 54
                    height: 54
                    name: f.model.name || f.model.address
                    unread: f.model.unread
                    scale: m.pressed ? 0.9 : f.model.tid === texts.open ? 1.08 : m.containsMouse ? 1.06 : 1
                    Behavior on scale { NumberAnimation { duration: 260; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.spring } }
                    Accessible.role: Accessible.Button
                    Accessible.name: name
                }
                MouseArea {
                    id: m
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        if (f.model.tid === texts.open) { closing.start(); texts.leave(); return }
                        f.model.unread = 0
                        texts.show({ id: f.model.tid, name: f.model.name, address: f.model.address })
                    }
                }
            }
        }
    }
    Shots { of: scene; what: faces.count > 0 ? "bubbles-" + (texts.open >= 0 ? "open" : "closed") : "" }
    Connections {
        target: texts
        enabled: Qt.application.arguments.indexOf("--open") > 0
        function onLoadingChanged() { if (!texts.loading && texts.open < 0 && texts.threads.count > 0) Qt.callLater(() => { const t = texts.threads.get(0); texts.show({ id: t.id, name: t.name, address: t.address }) }) }
    }
}
