// SPDX-License-Identifier: GPL-3.0-or-later
import QtQuick
import dev.pairlume

// Wide: the list and one more card. Narrow: one card at a time.
Item {
    id: v
    required property Texts texts
    readonly property bool wide: width >= 760
    readonly property bool talking: texts.open >= 0
    // someone who has just written while the list was all there is
    property var caller: null
    property var skipped: ({})
    // the first that waits and was not put off
    readonly property var waiter: { texts.tallied; for (let i = 0; i < texts.threads.count; i++) { const t = texts.threads.get(i); if (t.unread > 0 && skipped[t.id] !== t.date) return { id: t.id, name: t.name, address: t.address, snippet: t.snippet, date: t.date } } return null }
    property bool solid: false
    signal leave
    function copied(t) { clip.text = t; clip.selectAll(); clip.copy(); said.text = Tr.t("copied: %1").arg(t); quiet.restart() }
    function putOff(t) { const s = Object.assign({}, skipped); s[t.id] = t.date; skipped = s; caller = null }
    function go(t) { caller = null; texts.show({ id: t.id, name: t.name, address: t.address }) }
    TextEdit { id: clip; visible: false }
    Connections { target: v.texts; function onCame(thread, message) { if (!v.wide && !v.talking) v.caller = Object.assign({}, thread, { snippet: message.text, date: message.date }) } }

    Shortcut { sequences: ["Ctrl+K", "Ctrl+F"]; onActivated: people.search() }
    Shortcut { sequence: "Alt+Down"; onActivated: people.list.step(1) }
    Shortcut { sequence: "Alt+Up"; onActivated: people.list.step(-1) }
    Shortcut { sequence: "Ctrl+Shift+C"; onActivated: talk.copyCode() }
    Repeater { model: 9; Item { required property int index; Shortcut { sequence: "Alt+" + (parent.index + 1); onActivated: people.list.pickNth(parent.index) } } }
    Keys.onEscapePressed: { if (people.shut()) return; if (v.caller) v.putOff(v.caller); else if (v.talking) v.texts.leave(); else v.leave() }

    component Turn: Item {
        property bool on: true
        property int from: 24
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        opacity: on ? 1 : 0
        visible: opacity > 0
        enabled: on
        transform: Translate { x: on ? 0 : from; Behavior on x { NumberAnimation { duration: Theme.normal; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.smooth } } }
        Behavior on opacity { NumberAnimation { duration: Theme.quick } }
    }
    Turn {
        on: v.wide || (!v.talking && !v.caller && !v.texts.blocked)
        from: -24
        width: v.wide ? Math.max(340, Math.min(420, v.width * 0.36)) : v.width
        ListCard { id: people; alone: !v.wide; solid: v.solid; anchors.fill: parent; texts: v.texts; onChosen: t => v.go(t) }
        id: first
    }
    Turn {
        on: !v.talking && (v.wide || v.caller !== null || v.texts.blocked)
        anchors { left: v.wide ? first.right : parent.left; leftMargin: v.wide ? 12 : 0; right: parent.right }
        Moment { solid: v.solid; anchors.fill: parent; texts: v.texts; of: v.wide ? v.waiter : v.caller; onLater: v.putOff(of); onReply: v.go(of); onCopy: t => v.copied(t) }
    }
    Turn {
        on: v.talking
        anchors { left: v.wide ? first.right : parent.left; leftMargin: v.wide ? 12 : 0; right: parent.right }
        TalkCard { id: talk; solid: v.solid; anchors.fill: parent; texts: v.texts; back: !v.wide; onLeft_: v.texts.leave(); onCopy: t => v.copied(t) }
    }
    // a call covers what is on the right (or everything when narrow) while it lasts, and a little after
    property bool callShut: false
    Connections { target: v.texts; function onCalled() { v.callShut = false; if (v.texts.call.state === "ended") callAway.restart(); else callAway.stop() } }
    Timer { id: callAway; interval: v.texts.call && v.texts.call.missed ? 30000 : 4000; onTriggered: v.callShut = true }
    Turn {
        on: v.texts.call !== null && !v.callShut
        anchors { left: v.wide ? first.right : parent.left; leftMargin: v.wide ? 12 : 0; right: parent.right }
        z: 2
        CallCard {
            solid: v.solid
            anchors.fill: parent
            texts: v.texts
            onClose: v.callShut = true
            onWrite: t => {
                v.callShut = true
                for (let i = 0; i < v.texts.threads.count; i++) { const x = v.texts.threads.get(i); if (x.address === t.address) { v.go(x); return } }
                v.copied(t.address)
            }
        }
    }
    Rectangle {
        anchors { horizontalCenter: parent.horizontalCenter; bottom: parent.bottom; bottomMargin: 96 }
        opacity: quiet.running ? 1 : 0
        visible: opacity > 0
        Behavior on opacity { NumberAnimation { duration: Theme.quick } }
        width: said.width + 36
        height: 42
        radius: 21
        color: Theme.text
        Text { id: said; anchors.centerIn: parent; width: Math.min(implicitWidth, v.width - 90); elide: Text.ElideRight; textFormat: Text.PlainText; color: Theme.surface; font { pixelSize: 14; weight: Font.DemiBold } }
        Timer { id: quiet; interval: 1600 }
    }
}
