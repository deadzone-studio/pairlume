// SPDX-License-Identifier: GPL-3.0-or-later
import QtQuick
import QtQuick.Window
import org.kde.layershell as LayerShell
import dev.pairlume

// Waits in the background; when the phone rings, the call comes to the top of the screen. Started once with the desktop.
Window {
    id: win
    readonly property bool on: texts.call !== null && !shut
    property bool shut: false
    LayerShell.Window.scope: "pairlume"
    LayerShell.Window.layer: LayerShell.Window.LayerOverlay
    LayerShell.Window.anchors: LayerShell.Window.AnchorTop
    LayerShell.Window.margins.top: 12
    LayerShell.Window.keyboardInteractivity: LayerShell.Window.KeyboardInteractivityNone
    LayerShell.Window.exclusionZone: -1
    title: Tr.t("Calls")
    width: 440
    height: 540
    color: "transparent"
    visible: on || away.running
    Service { id: service; onBlurredChanged: Theme.blurred = blurred; onColorsChanged: { try { Theme.from = JSON.parse(colors) } catch (e) { console.warn("colors: " + e) } } }
    Texts { id: texts; service: service; onCalled: { win.shut = false; if (call.state === "ended") later.restart(); else later.stop() } }
    // an ended call goes by itself; a missed one stays a while longer
    Timer { id: later; interval: texts.call && texts.call.missed ? 20000 : 4000; onTriggered: win.shut = true }
    Item {
        id: scene
        anchors.fill: parent
        CallCard {
            id: card
            texts: texts
            width: 420
            height: 520
            anchors.horizontalCenter: parent.horizontalCenter
            y: win.on ? 10 : -height - 20
            opacity: win.on ? 1 : 0
            Behavior on y { NumberAnimation { id: away; duration: Theme.normal; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.spring } }
            Behavior on opacity { NumberAnimation { duration: Theme.quick } }
            onClose: win.shut = true
            onWrite: t => { win.shut = true; service.writeTo(t.address) }
        }
    }
    Shots { of: scene; what: texts.call ? "call-" + texts.call.state + (texts.call.missed ? "-missed" : "") : "" }
}
