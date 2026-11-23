// SPDX-License-Identifier: GPL-3.0-or-later
import QtQuick
import dev.pairlume

// The texts of the connected phone: only in memory, only as long as a window needs them.
Item {
    id: tx
    required property Service service
    property string device
    property string deviceName
    property bool online: false
    // the phone is there, but this computer has not said yes to texts
    property bool blocked: false
    // calls: may this phone use them, and the call there is now ({ state, number, name, missed, png, since }), or null
    property bool mayCall: false
    property var call: null
    property string callTrouble
    // Bluetooth pairing for the voice of calls: { name, code } while the computer waits for a yes, then { ok }
    property var bt: null
    function btAnswer(yes) { ask("bt", { cmd: "bt_answer", yes: yes }) }
    signal called
    function callDo(what, number) {
        callTrouble = ""
        if (device === "") return
        const r = { cmd: "call", device: device, what: what }
        if (number) r.number = number
        ask("call", r)
    }
    property int battery: -1
    property bool charging: false
    // conversations with something to read
    property int waiting: 0
    function tally() { let n = 0; for (let i = 0; i < threads.count; i++) if (threads.get(i).unread > 0) n++; waiting = n; tallied++ }
    property int tallied: 0
    property string trouble: Tr.t("Pairlume is not running")
    property bool loading: false
    property bool more: false
    property int open: -1              // the conversation that is open (its id)
    property var head: null            // { id, name, address }
    property bool moreBefore: false
    property int sent: 0               // numbers for texts on their way
    property int round: 0              // answers for a conversation that was left are not for this one
    readonly property ListModel threads: ListModel {}
    readonly property ListModel messages: ListModel {}
    signal came(var thread, var message)

    // pictures from the contacts, by number; asked for a few at a time
    property var faces: ({})
    property var wanted: []
    property bool fetching: false
    function face(address) { return faces[address] || "" }
    function wantFace(t) { if (t.name !== "" && !(t.address in faces) && !wanted.includes(t.address)) { wanted.push(t.address); nextFaces() } }
    function nextFaces() {
        if (fetching || !online || wanted.length === 0) return
        fetching = true
        const some = wanted.slice(0, 5)
        ask("faces " + some.length, { cmd: "sms_photos", device: device, addresses: some })
    }
    function title(t) { return t.name || t.address }
    function when(ms) {
        const d = new Date(ms), now = new Date()
        if (d.toDateString() === now.toDateString()) return Qt.formatTime(d, "HH:mm")
        if (new Date(now - 864e5).toDateString() === d.toDateString()) return Tr.t("Yesterday")
        return now - d < 6 * 864e5 ? d.toLocaleDateString(Qt.locale(), "dddd") : d.toLocaleDateString(Qt.locale(), d.getFullYear() === now.getFullYear() ? "d MMM" : "d MMM yyyy")
    }
    function ago(ms) { return Date.now() - ms < 12e4 ? Tr.t("just now") : when(ms) }
    // the code in a text: 4 to 8 digits that stand alone, in a text that speaks of one, and are not a year or a piece of a phone number
    function code(s) {
        if (!/code|kod|haslo|hasło|pin|otp|verif|weryfik|autory/i.test(s)) return ""
        const re = /(?:^|[^0-9+\/.,])([0-9]{4,8})(?![0-9\/]|[ -][0-9]{3})/g
        let m
        while ((m = re.exec(s)) !== null) if (!/^(19|20)[0-9]{2}$/.test(m[1])) return m[1]
        return ""
    }
    // of the open conversation, when it has come today
    function lastCode() {
        for (let i = messages.count - 1; i >= Math.max(0, messages.count - 6); i--) { const m = messages.get(i); if (!m.out && Date.now() - m.date < 864e5) { const c = code(m.body); if (c !== "") return c } }
        return ""
    }
    function ask(tag, r) { service.askFor(tag, JSON.stringify(r)) }
    function allowSms() { if (device !== "") ask("allow", { cmd: "allow", device: device, cap: "sms", on: true }) }
    function look() { ask("status", { cmd: "status" }) }
    function refresh() { if (!online) return; loading = threads.count === 0; ask("threads", { cmd: "sms_threads", device: device, before: null }) }
    function older() { if (more && !loading && threads.count > 0) { loading = true; ask("older", { cmd: "sms_threads", device: device, before: threads.get(threads.count - 1).date }) } }
    function show(t) {
        round++
        open = t.id
        head = { id: t.id, name: t.name, address: t.address }
        messages.clear()
        moreBefore = false
        for (let i = 0; i < threads.count; i++) if (threads.get(i).id === t.id) threads.setProperty(i, "unread", 0)
        tally()
        ask("read " + round, { cmd: "sms_messages", device: device, thread: t.id, before: null })
    }
    function leave() { round++; open = -1; head = null; messages.clear() }
    function earlier() { if (moreBefore && messages.count > 0) { moreBefore = false; ask("earlier " + round, { cmd: "sms_messages", device: device, thread: open, before: messages.get(0).date }) } }
    function row(m, state) { return { id: m.id, out: m.out, body: m.text, date: m.date, state: state || (m.failed ? "failed" : "") , tag: 0, fresh: false } }
    function send(text) {
        if (!head || text.trim() === "") return
        const n = ++sent
        messages.append({ id: -n, out: true, body: text, date: Date.now(), state: "going", tag: n, fresh: true })
        ask("sent " + n, { cmd: "sms_send", device: device, to: head.address, text: text })
        up({ id: head.id, name: head.name, address: head.address, snippet: text, date: Date.now(), unread: 0 })
    }
    // a conversation that has something new goes to the top
    function up(t) {
        for (let i = 0; i < threads.count; i++) if (threads.get(i).id === t.id) { threads.set(i, t); if (i > 0) threads.move(i, 0, 1); return }
        threads.insert(0, t)
    }
    function mark(n, state) { for (let i = messages.count - 1; i >= 0; i--) if (messages.get(i).tag === n) { messages.setProperty(i, "state", state); return } }

    Component.onCompleted: service.start()
    Connections {
        target: tx.service
        function onConnectedChanged() {
            if (tx.service.connected) tx.look()
            else { tx.online = false; tx.trouble = Tr.t("Pairlume is not running") }
        }
        function onHappened(json) {
            const e = JSON.parse(json)
            if (["online", "offline", "paired", "unpaired", "allowed", "battery"].includes(e.event)) tx.look()
            if (e.event === "bt_code") tx.bt = { name: e.name, code: e.code }
            if (e.event === "bt_done") tx.bt = { ok: e.ok, name: tx.bt ? tx.bt.name : "" }
            if (e.event === "call" && e.id === tx.device) {
                const was = tx.call
                const c = { state: e.state, number: e.number, name: e.name, missed: e.missed, png: e.png ? "data:image/png;base64," + e.png : (was && was.number === e.number ? was.png : ""),
                            since: was && was.state === e.state ? was.since : Date.now() }
                if (e.png) { const f = Object.assign({}, tx.faces); f[e.number] = c.png; tx.faces = f }
                tx.call = c
                tx.called()
            }
            if (e.event === "sms" && e.id === tx.device) {
                const here = e.thread.id === tx.open
                tx.up(Object.assign({}, e.thread, { unread: here ? 0 : e.thread.unread }))
                if (here) { const r = tx.row(e.message); r.fresh = true; tx.messages.append(r) }
                tx.wantFace(e.thread)
                tx.tally()
                tx.came(e.thread, e.message)
            }
        }
        function onReplied(tag, json) {
            const r = JSON.parse(json), kind = tag.split(" ")[0], n = parseInt(tag.split(" ")[1] || "0")
            if (kind === "status") {
                const d = r.devices || [], s = d.find(x => x.online && x.allowed.includes("sms")) || d.find(x => x.online) || d[0]
                const may = s && s.allowed.includes("sms")
                const was = tx.online ? tx.device : ""
                tx.device = s ? s.id : ""
                tx.deviceName = s ? s.name : ""
                tx.online = !!(s && s.online && may)
                tx.blocked = !!(s && s.online && !may)
                tx.mayCall = !!(s && s.online && s.allowed.includes("calls"))
                if (!tx.mayCall) tx.call = null
                // a window opened in the middle of a call
                else if (s.call && !tx.call) { tx.call = { state: s.call.state, number: s.call.number, name: s.call.name, missed: false, png: "", since: Date.now() }; tx.wantFace({ name: s.call.name, address: s.call.number }); tx.called() }
                tx.battery = s && s.battery ? s.battery[0] : -1
                tx.charging = !!(s && s.battery && s.battery[1])
                tx.trouble = !s ? Tr.t("No phone is paired yet") : !s.online ? Tr.t("%1 is not connected").arg(s.name)
                           : !may ? Tr.t("Texts are off on this computer") : ""
                if (tx.device !== was) { if (tx.online) tx.refresh(); if (was !== "" && tx.device !== "") { tx.threads.clear(); tx.leave() } }
                return
            }
            if (kind === "call") { if (r.error || r.why) tx.callTrouble = r.error || r.why; return }
            if (kind === "allow") { if (r.error || r.why) tx.trouble = r.error || r.why; tx.look(); return }
            const a = r.answer
            if (kind === "threads" || kind === "older") {
                if (!a) { tx.trouble = r.why || ""; tx.loading = false; return }
                tx.trouble = ""
                if (kind === "threads") tx.threads.clear()
                a.threads.forEach(t => { tx.threads.append(t); tx.wantFace(t) })
                tx.more = a.more
                tx.tally()
                tx.loading = false
            } else if (kind === "read" || kind === "earlier") {
                if (n !== tx.round || !a) return
                tx.moreBefore = a.more
                a.messages.slice().reverse().forEach(m => tx.messages.insert(0, tx.row(m)))
            } else if (kind === "faces") {
                tx.fetching = false
                const f = Object.assign({}, tx.faces)
                tx.wanted.splice(0, n).forEach(x => { if (!(x in f)) f[x] = "" })
                if (a) a.faces.forEach(x => { f[x.address] = "data:image/png;base64," + x.png })
                tx.faces = f
                tx.nextFaces()
            } else if (kind === "sent") {
                // no answer in time: it may have gone out. Saying "failed" could make someone send it twice
                tx.mark(n, a ? "" : /did not answer|went away/.test(r.why || "") ? "unsure" : "failed")
            }
        }
    }
}
