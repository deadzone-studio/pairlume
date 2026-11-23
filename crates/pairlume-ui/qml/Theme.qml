// SPDX-License-Identifier: GPL-3.0-or-later
pragma Singleton
import QtQuick

// Colors (from the wallpaper when matugen writes them) and how things move.
QtObject {
    id: th
    property var from: ({})
    property bool blurred: false
    function pick(keys, d) {
        for (const k of keys) { const v = from[k]; if (typeof v === "string" && /^#[0-9a-f]{6}$/i.test(v)) return v }
        return d
    }
    readonly property color given: pick(["surface_low", "surface"], "#0e1424")
    readonly property bool dark: given.hslLightness < 0.5
    readonly property color accent: vivid(pick(["accent", "primary"], "#7aa2ff"))
    readonly property color accent2: vivid(pick(["accent2", "tertiary"], "#c08bff"))
    readonly property real hue: Math.max(0, accent.hslHue)
    readonly property real sat: Math.min(0.42, accent.hslSaturation * 0.45)
    // palettes from a wallpaper have gray surfaces and pale accents: deep ones of the same hue instead
    readonly property color surface: dark ? Qt.hsla(hue, sat, 0.1, 1) : given
    // what the cards of a window stand on
    readonly property color ground: dark ? Qt.hsla(hue, sat, 0.25, 1) : mix(given, accent, 0.25)
    readonly property color text: pick(["text", "on_surface"], "#e8edf8")
    readonly property color dim: pick(["dim", "on_surface_variant"], "#9aa6c4")
    // on top of the accent color
    readonly property color ink: dark ? Qt.hsla(hue, sat, 0.07, 1) : pick(["on_accent", "on_primary"], "#ffffff")
    function vivid(c) { c = Qt.color(c); return dark && c.hslSaturation > 0.15 ? Qt.hsla(c.hslHue, Math.max(0.72, c.hslSaturation), Math.min(0.74, c.hslLightness), 1) : c }
    readonly property color bad: pick(["error"], "#ff8a8a")
    // how solid the glass is: thin only where the compositor blurs behind it
    readonly property real glass: typeof from.glass === "number" ? Math.max(0.2, Math.min(1, from.glass)) : blurred ? 0.5 : 0.95
    function fade(c, a) { return Qt.rgba(c.r, c.g, c.b, a) }
    function mix(a, b, t) { return Qt.rgba(a.r + (b.r - a.r) * t, a.g + (b.g - a.g) * t, a.b + (b.b - a.b) * t, 1) }
    // springy on the way in, short on the way out
    readonly property var spring: [0.2, 1.35, 0.3, 1, 1, 1]
    readonly property var smooth: [0.2, 0, 0, 1, 1, 1]
    readonly property int quick: 180
    readonly property int normal: 420
    readonly property int slow: 800
}
