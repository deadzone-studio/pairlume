// SPDX-License-Identifier: GPL-3.0-or-later
import QtQuick
import QtQuick.Window

// Layers cannot be moved by the compositor: dragging this moves the window by its margins (`spotX`, `spotY` of `win`).
MouseArea {
    id: m
    required property Window win
    property real sx
    property real sy
    cursorShape: pressed ? Qt.ClosedHandCursor : Qt.ArrowCursor
    onPressed: e => { sx = e.x; sy = e.y }
    onPositionChanged: e => {
        if (!pressed) return
        win.spotX = Math.max(0, Math.min(win.Screen.width - win.width, win.spotX + e.x - sx))
        win.spotY = Math.max(0, Math.min(win.Screen.height - win.height, win.spotY + e.y - sy))
    }
    onReleased: win.moved()
}
