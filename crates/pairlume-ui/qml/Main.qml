// SPDX-License-Identifier: GPL-3.0-or-later
import QtQuick
import QtQuick.Window
import org.kde.layershell as LayerShell
import dev.pairlume

Window {
    id: win
    LayerShell.Window.scope: "pairlume"
    LayerShell.Window.layer: LayerShell.Window.LayerOverlay
    LayerShell.Window.anchors: LayerShell.Window.AnchorNone
    LayerShell.Window.keyboardInteractivity: LayerShell.Window.KeyboardInteractivityOnDemand
    LayerShell.Window.exclusionZone: -1
    title: "Pairlume"
    width: 460
    height: 600
    color: "transparent"
    visible: true
    function leave() { if (out.running) return; card.stop(); out.start() }

    Service {
        id: service
        onColorsChanged: { try { Theme.from = JSON.parse(colors) } catch (e) { console.warn("colors.json: " + e) } }
        Component.onCompleted: start()
    }
    Shots { of: scene; what: card.step + "-" + card.how }

    Item {
        id: scene
        anchors.fill: parent
        focus: true
        Keys.onEscapePressed: win.leave()
        PairingCard {
            id: card
            service: service
            anchors.centerIn: parent
            onClosed: win.leave()
            // --how qr: start with another way
            Component.onCompleted: { const a = Qt.application.arguments, i = a.indexOf("--how"); if (i > 0 && ["qr", "digits"].includes(a[i + 1])) how = a[i + 1] }
            opacity: 0
            scale: 0.86
            ParallelAnimation {
                running: true
                NumberAnimation { target: card; property: "opacity"; to: 1; duration: 220 }
                NumberAnimation { target: card; property: "scale"; to: 1; duration: 560; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.spring }
            }
            SequentialAnimation {
                id: out
                ParallelAnimation {
                    NumberAnimation { target: card; property: "opacity"; to: 0; duration: 180 }
                    NumberAnimation { target: card; property: "scale"; to: 0.92; duration: 180; easing.type: Easing.InCubic }
                }
                // the last request still has to reach the service
                PauseAnimation { duration: 120 }
                ScriptAction { script: Qt.quit() }
            }
        }
    }
}
