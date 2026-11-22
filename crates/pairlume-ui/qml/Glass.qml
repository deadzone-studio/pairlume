// SPDX-License-Identifier: GPL-3.0-or-later
import QtQuick
import dev.pairlume

// A piece of glass: a thin tint, a bright upper edge, a hairline around it.
Rectangle {
    id: g
    property real lift: 0.08
    color: Theme.fade(Theme.text, lift)
    border { width: 1; color: Theme.fade(Theme.text, 0.1) }
    Rectangle {
        anchors { fill: parent; margins: 1 }
        radius: Math.max(0, g.radius - 1)
        gradient: Gradient {
            GradientStop { position: 0; color: Theme.fade(Theme.text, 0.09) }
            GradientStop { position: 0.45; color: Theme.fade(Theme.text, 0) }
        }
    }
}
