// SPDX-License-Identifier: GPL-3.0-or-later
import QtQuick
import QtQuick.Window
import org.kde.layershell as LayerShell
import dev.pairlume

// pairlume-ui notifications: waits in the background; a notification of the phone comes in at the top right, stays a
// few seconds (longer while the mouse is on it or an answer is being written) and goes. Started once with the desktop.
Window {
    id: win
    LayerShell.Window.scope: "pairlume"
    LayerShell.Window.layer: LayerShell.Window.LayerOverlay
    LayerShell.Window.anchors: LayerShell.Window.AnchorTop | LayerShell.Window.AnchorRight
    LayerShell.Window.margins.top: 12
    LayerShell.Window.margins.right: 12
    LayerShell.Window.keyboardInteractivity: shown.count > 0 ? LayerShell.Window.KeyboardInteractivityOnDemand : LayerShell.Window.KeyboardInteractivityNone
    LayerShell.Window.exclusionZone: -1
    title: Tr.t("Notifications")
    width: 404
    height: Math.max(1, list.contentHeight + 24)
    color: "transparent"
    visible: shown.count > 0 || hiding.running
    Service { id: service; onBlurredChanged: Theme.blurred = blurred; onColorsChanged: { try { Theme.from = JSON.parse(colors) } catch (e) { } } }
    Texts { id: texts; service: service; onNotified: n => win.show(n) }
    Component.onCompleted: if (Qt.application.arguments.indexOf("--shots") < 0 && !service.claim("notifications", "[]")) Qt.callLater(Qt.quit)
    // the ones on the screen now, at most three; the newest on top
    ListModel { id: shown }
    Timer { id: hiding; interval: Theme.normal }
    function show(n) {
        for (let i = 0; i < shown.count; i++) if (shown.get(i).key === n.key) { shown.remove(i); break }
        shown.insert(0, { key: n.key, app: n.app, appName: n.app_name || n.app, title: n.title || "", text: n.text || "", when: n.when || Date.now(),
                          actions: JSON.stringify(n.actions || []), until: Date.now() + 8000 })
        while (shown.count > 3) shown.remove(shown.count - 1)
    }
    function drop(key) { for (let i = 0; i < shown.count; i++) if (shown.get(i).key === key) { shown.remove(i); hiding.restart(); return } }
    Connections {
        target: texts.notifs
        // gone on the phone: gone here
        function onRowsRemoved() { for (let i = shown.count - 1; i >= 0; i--) { let k = shown.get(i).key, there = false; for (let j = 0; j < texts.notifs.count; j++) if (texts.notifs.get(j).key === k) there = true; if (!there) win.drop(k) } }
    }
    Timer {
        interval: 500; repeat: true; running: shown.count > 0
        onTriggered: { const now = Date.now(); for (let i = shown.count - 1; i >= 0; i--) { const c = list.itemAtIndex(i); if (c && c.busy) shown.setProperty(i, "until", now + 4000); else if (shown.get(i).until < now) win.drop(shown.get(i).key) } }
    }
    readonly property Texts phone: texts
    Item {
        id: scene
        anchors.fill: parent
        ListView {
            id: list
            anchors { fill: parent; topMargin: 12; rightMargin: 12; leftMargin: 12 }
            spacing: 10
            interactive: false
            model: shown
            add: Transition { NumberAnimation { property: "x"; from: 420; duration: 520; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.spring } }
            remove: Transition { NumberAnimation { property: "opacity"; to: 0; duration: Theme.quick } }
            displaced: Transition { NumberAnimation { property: "y"; duration: Theme.normal; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.smooth } }
            // win.phone, not texts: inside the card that name is the card's own property
            delegate: NotifCard { required property int index; texts: win.phone; onClosed: win.drop(model.key) }
        }
    }
    Shots { of: scene; what: shown.count > 0 ? "notifs-" + shown.count : "" }
}
