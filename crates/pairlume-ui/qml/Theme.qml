// SPDX-License-Identifier: GPL-3.0-or-later
pragma Singleton
import QtQuick

// Colors (from the wallpaper when matugen writes them) and how things move.
QtObject {
    id: th
    property var from: ({})
    function pick(k, d) { const v = from[k]; return typeof v === "string" && /^#[0-9a-f]{6}$/i.test(v) ? v : d }
    readonly property color surface: pick("surface", "#0e1424")
    readonly property color text: pick("text", "#e8edf8")
    readonly property color dim: pick("dim", "#9aa6c4")
    readonly property color accent: pick("accent", "#7aa2ff")
    readonly property color accent2: pick("accent2", "#c08bff")
    // on top of the accent color
    readonly property color ink: pick("on_accent", "#0b1020")
    readonly property color bad: pick("error", "#ff8a8a")
    // how solid the glass is: thin only where the compositor blurs behind it (docs/hyprland.md)
    readonly property real glass: typeof from.glass === "number" ? Math.max(0.3, Math.min(1, from.glass)) : 0.94
    function fade(c, a) { return Qt.rgba(c.r, c.g, c.b, a) }
    // springy on the way in, short on the way out
    readonly property var spring: [0.2, 1.35, 0.3, 1, 1, 1]
    readonly property var smooth: [0.2, 0, 0, 1, 1, 1]
    readonly property int quick: 180
    readonly property int normal: 420
    readonly property int slow: 800
}
