// SPDX-License-Identifier: GPL-3.0-or-later
import QtQuick
import QtQuick.Window
import org.kde.layershell as LayerShell
import dev.pairlume

// pairlume-ui notifications: waits in the background; a notification of the phone comes in, stays a few seconds (longer
// while the mouse is on it, an answer is being written or its bar moves) and goes. Started once with the desktop.
// Two looks, chosen in the settings and followed at once: cards at the top right, or banners at the top in the middle
// like texts on an iPhone.
Window {
    id: win
    LayerShell.Window.scope: "pairlume"
    LayerShell.Window.layer: LayerShell.Window.LayerOverlay
    // "system": the desktop's own notifications show them; this window only opens for an answer, as a banner
    readonly property bool system: Tr.notifStyle === "system"
    readonly property bool banner: Tr.notifStyle === "banner" || system
    LayerShell.Window.anchors: banner ? LayerShell.Window.AnchorTop : LayerShell.Window.AnchorTop | LayerShell.Window.AnchorRight
    LayerShell.Window.margins.top: banner ? 6 : 12
    LayerShell.Window.margins.right: banner ? 0 : 12
    LayerShell.Window.keyboardInteractivity: shown.count > 0 ? LayerShell.Window.KeyboardInteractivityOnDemand : LayerShell.Window.KeyboardInteractivityNone
    LayerShell.Window.exclusionZone: -1
    title: Tr.t("Notifications")
    width: banner ? 448 : 404
    height: Math.max(1, list.contentHeight + 24)
    color: "transparent"
    visible: shown.count > 0 || hiding.running
    Service {
        id: service
        onBlurredChanged: Theme.blurred = blurred
        onColorsChanged: { try { Theme.from = JSON.parse(colors) } catch (e) { } }
        onSysPressed: (key, action) => win.pressed(key, action)
    }
    // the system look: what each notification there was, to act on a pressed button
    property var given: ({})
    function toSystem(n) {
        const acts = n.actions || [], code = texts.code((n.title || "") + " " + (n.text || ""))
        const list = []
        if (code !== "") list.push(["copy", Tr.t("Copy %1").arg(code)])
        acts.forEach((a, i) => list.push([a.reply ? "reply" + i : "a" + i, a.title || ""]))
        list.push(["dismiss", Tr.t("Dismiss")])
        const p = n.progress || null
        const icon = texts.notifIcon(n.app).replace(/^data:image\/png;base64,/, "")
        const g = Object.assign({}, given); g[n.key] = Object.assign({}, n, { code: code }); given = g
        service.sysShow(JSON.stringify({ key: n.key, app: n.app, app_name: n.app_name || n.app, title: n.title || "", text: n.text || "", icon: icon,
                                         actions: list, value: p && !p.busy && p.max > 0 ? Math.round(100 * p.value / p.max) : undefined }))
    }
    function pressed(key, action) {
        const n = given[key]
        if (!n) return
        if (action === "copy") { if (!service.copyText(n.code)) { clip.text = n.code; clip.selectAll(); clip.copy() } }
        else if (action === "dismiss") texts.notifDo(key, "dismiss")
        else if (action.startsWith("reply")) show(n, true)
        else if (action.startsWith("a")) texts.notifDo(key, "action", parseInt(action.slice(1)))
        else if (action === "default") show(n, true)
    }
    TextEdit { id: clip; visible: false }
    Texts { id: texts; service: service; onNotified: n => win.system ? win.toSystem(n) : win.show(n) }
    Component.onCompleted: if (Qt.application.arguments.indexOf("--shots") < 0 && !service.claim("notifications", "[]")) Qt.callLater(Qt.quit)
    // the ones on the screen now, at most three; the newest on top
    ListModel { id: shown }
    Timer { id: hiding; interval: Theme.normal }
    function show(n, answer) {
        const p = n.progress || null
        const row = { key: n.key, app: n.app, appName: n.app_name || n.app, title: n.title || "", text: n.text || "", when: n.when || Date.now(),
                      actions: JSON.stringify(n.actions || []), until: Date.now() + 8000,
                      pMax: p ? (p.max || 0) : 0, pValue: p ? (p.value || 0) : 0, pBusy: p ? !!p.busy : false, answer: !!answer }
        // the same one again (its bar moved, its words changed): changed where it is, so nothing jumps
        for (let i = 0; i < shown.count; i++) if (shown.get(i).key === n.key) { shown.set(i, row); return }
        shown.insert(0, row)
        while (shown.count > 3) shown.remove(shown.count - 1)
    }
    function drop(key) { for (let i = 0; i < shown.count; i++) if (shown.get(i).key === key) { shown.remove(i); hiding.restart(); return } }
    Connections {
        target: texts.notifs
        // gone on the phone: gone here; an update takes a notification out and puts it back at once: look only after that
        function onRowsRemoved() { Qt.callLater(win.gone) }
    }
    function gone() {
        // gone on the phone: gone from the desktop's notifications too
        const g = Object.assign({}, given)
        for (const k in g) { let there = false; for (let j = 0; j < texts.notifs.count; j++) if (texts.notifs.get(j).key === k) there = true; if (!there) { service.sysClose(k); delete g[k] } }
        given = g
        for (let i = shown.count - 1; i >= 0; i--) { let k = shown.get(i).key, there = false; for (let j = 0; j < texts.notifs.count; j++) if (texts.notifs.get(j).key === k) there = true; if (!there) win.drop(k) } }
    Timer {
        interval: 500; repeat: true; running: shown.count > 0
        // a bar that still moves keeps it up too
        onTriggered: { const now = Date.now(); for (let i = shown.count - 1; i >= 0; i--) { const c = list.itemAtIndex(i), r = shown.get(i), moving = r.pBusy || (r.pMax > 0 && r.pValue < r.pMax); if ((c && c.busy) || moving) shown.setProperty(i, "until", now + 4000); else if (r.until < now) win.drop(r.key) } }
    }
    readonly property Texts phone: texts
    Item {
        id: scene
        anchors.fill: parent
        ListView {
            id: list
            anchors { fill: parent; topMargin: win.banner ? 6 : 12; rightMargin: 12; leftMargin: 12 }
            spacing: 10
            interactive: false
            model: shown
            // a card comes in from the right; a banner drops from the top
            add: Transition {
                NumberAnimation { property: win.banner ? "y" : "x"; from: win.banner ? -120 : 420; duration: 520; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.spring }
            }
            remove: Transition { NumberAnimation { property: "opacity"; to: 0; duration: Theme.quick } }
            displaced: Transition { NumberAnimation { property: "y"; duration: Theme.normal; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.smooth } }
            // win.phone, not texts: inside the card that name is the card's own property
            delegate: Item {
                id: one
                required property int index
                required property var model
                readonly property bool busy: win.banner ? b.busy : c.busy
                width: list.width
                height: win.banner ? b.height : c.height
                NotifCard { id: c; visible: !win.banner; anchors.horizontalCenter: parent.horizontalCenter; texts: win.phone; model: one.model; onClosed: win.drop(one.model.key) }
                NotifBanner { id: b; visible: win.banner; anchors.horizontalCenter: parent.horizontalCenter; texts: win.phone; model: one.model; onClosed: win.drop(one.model.key) }
            }
        }
    }
    Shots { of: scene; what: shown.count > 0 ? "notifs-" + shown.count : "" }
}
