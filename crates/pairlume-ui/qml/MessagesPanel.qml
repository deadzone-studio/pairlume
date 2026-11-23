// SPDX-License-Identifier: GPL-3.0-or-later
import QtQuick
import QtQuick.Window
import org.kde.layershell as LayerShell
import dev.pairlume

// The same, from the right edge of the screen.
Window {
    id: win
    LayerShell.Window.scope: "pairlume"
    LayerShell.Window.layer: LayerShell.Window.LayerTop
    LayerShell.Window.anchors: LayerShell.Window.AnchorRight | LayerShell.Window.AnchorTop | LayerShell.Window.AnchorBottom
    LayerShell.Window.keyboardInteractivity: LayerShell.Window.KeyboardInteractivityOnDemand
    LayerShell.Window.exclusionZone: 0
    title: Tr.t("Messages")
    width: 420
    height: 800
    color: "transparent"
    visible: true
    function leave() { if (!out.running) out.start() }
    Service { id: service; onBlurredChanged: Theme.blurred = blurred; onColorsChanged: { try { Theme.from = JSON.parse(colors) } catch (e) { console.warn("colors: " + e) } } }
    Texts { id: texts; service: service }
    Item {
        id: scene
        anchors.fill: parent
        MessagesView {
            id: view
            width: parent.width - 20
            height: parent.height - 20
            y: 10
            x: parent.width
            texts: texts
            focus: true
            onLeave: win.leave()
            NumberAnimation { target: view; property: "x"; to: 10; running: true; duration: 520; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.spring }
        }
        SequentialAnimation {
            id: out
            NumberAnimation { target: view; property: "x"; to: win.width; duration: 220; easing.type: Easing.InCubic }
            ScriptAction { script: Qt.quit() }
        }
    }
    Shots { of: scene; what: texts.open >= 0 ? "panel-" + texts.open : texts.threads.count > 0 ? "panel" : "" }
}
