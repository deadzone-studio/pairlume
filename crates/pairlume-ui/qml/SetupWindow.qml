// SPDX-License-Identifier: GPL-3.0-or-later
import QtQuick
import QtQuick.Window
import dev.pairlume

// pairlume-ui setup --from <release folder>: the installer, a card like the pairing one, a step at a time. All the work
// is done by install.sh of the release, so the window and the terminal do the same.
Window {
    id: win
    title: Tr.t("Install Pairlume")
    width: 480
    height: 700
    // a fixed size: tiling desktops (Hyprland, Sway) then float it like a dialog instead of filling half the screen
    minimumWidth: 480; maximumWidth: 480
    minimumHeight: 700; maximumHeight: 700
    color: Theme.ground
    visible: false
    readonly property string from: { const a = Qt.application.arguments, i = a.indexOf("--from"); return i > 0 ? a[i + 1] : "" }
    property var info: ({})
    // lang | menu | options | work | phone | remove | gone
    property string step: "lang"
    property string lang: Tr.lang
    property bool calls: true
    property bool menu: true
    property bool pairAfter: true
    property bool forget: false
    property bool removing: false
    property bool failed: false
    property bool cabling: false
    property var lines: []
    readonly property var langs: { try { return JSON.parse(service.languages()) } catch (e) { return [] } }
    function look() { try { info = JSON.parse(service.setupInfo(from)) } catch (e) { info = {} } }
    function run(args) { lines = []; failed = false; service.runInstaller(from, JSON.stringify(args.concat(["--lang", lang]))) }
    function install() { removing = false; step = "work"; run(["--yes"].concat(calls ? [] : ["--no-calls"]).concat(menu ? [] : ["--no-menu"])) }
    function remove() { removing = true; step = "work"; run(["--remove"].concat(forget ? ["--purge"] : [])) }

    Service {
        id: service
        onBlurredChanged: Theme.blurred = blurred
        onColorsChanged: { try { Theme.from = JSON.parse(colors) } catch (e) { } }
        onSaid: line => { const l = line.trim(); if (l !== "") win.lines = win.lines.concat([l]) }
        onEnded: code => {
            win.failed = code !== 0
            win.look()
            if (win.cabling) { win.cabling = false; return }
            if (!win.failed) win.step = win.removing ? "gone" : "phone"
        }
    }
    Component.onCompleted: {
        if (Qt.application.arguments.indexOf("--shots") < 0 && !service.claim("setup", "[]")) { Qt.callLater(Qt.quit); return }
        Tr.pinned = true
        look()
        // --step <name>: for pictures of a step
        const a = Qt.application.arguments, i = a.indexOf("--step")
        if (i > 0) step = a[i + 1]
        // --chosen: the language was picked in the terminal already
        else if (a.indexOf("--chosen") > 0) step = info.installed ? "menu" : "options"
        visible = true
        service.start()
    }
    Connections { target: service; function onAgain(args) { service.front() } }
    TextEdit { id: clip; visible: false }
    function copy(t) { clip.text = t; clip.selectAll(); clip.copy() }

    // ---------- small pieces ----------
    // a line to choose, with the ring of the pairing phone when chosen
    component Choice: Item {
        id: ch
        property string label
        property string hint
        property bool on: false
        property bool round: true
        property bool go: false   // a way on, not a choice: an arrow instead of a box
        signal picked
        width: parent ? parent.width : 0
        height: hint === "" ? 54 : 68
        Accessible.role: round ? Accessible.RadioButton : Accessible.CheckBox
        Accessible.name: label
        Accessible.checked: on
        activeFocusOnTab: true
        Keys.onSpacePressed: picked()
        Keys.onReturnPressed: picked()
        Rectangle { anchors { fill: parent; topMargin: 2; bottomMargin: 2 } radius: 22; color: ch.on ? Theme.fade(Theme.accent, 0.16) : Theme.fade(Theme.text, cm.containsMouse ? 0.06 : 0); border { width: ch.activeFocus ? 2 : 0; color: Theme.text } }
        Rectangle {
            visible: !ch.go
            x: 14; anchors.verticalCenter: parent.verticalCenter
            width: 22; height: 22; radius: ch.round ? 11 : 7
            color: !ch.round && ch.on ? Theme.accent : "transparent"
            border { width: 2; color: ch.on ? Theme.accent : Theme.fade(Theme.text, 0.35) }
            Rectangle { anchors.centerIn: parent; width: 10; height: 10; radius: 5; color: Theme.accent; visible: ch.round && ch.on }
            Text { anchors.centerIn: parent; visible: !ch.round && ch.on; text: "✓"; color: Theme.ink; font { pixelSize: 14; weight: Font.Bold } }
        }
        Column {
            x: ch.go ? 20 : 50; anchors.verticalCenter: parent.verticalCenter
            width: parent.width - x - 40
            Text { width: parent.width; text: ch.label; textFormat: Text.PlainText; elide: Text.ElideRight; color: Theme.text; font { pixelSize: 15; weight: ch.on ? Font.DemiBold : Font.Normal } }
            Text { width: parent.width; visible: ch.hint !== ""; text: ch.hint; textFormat: Text.PlainText; elide: Text.ElideRight; color: Theme.dim; font.pixelSize: 12 }
        }
        Text { visible: ch.go; anchors { right: parent.right; rightMargin: 18; verticalCenter: parent.verticalCenter } text: "›"; color: Theme.dim; font.pixelSize: 24 }
        MouseArea { id: cm; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: ch.picked() }
    }

    Item {
        id: scene
        anchors.fill: parent
        Card {
            id: card
            anchors { fill: parent; margins: 12 }
            solid: true
            title: ({ lang: "Pairlume " + (win.info.version || ""), menu: Tr.t("Pairlume is installed"), options: Tr.t("What to install"),
                      work: win.failed ? Tr.t("That did not work") : win.removing ? Tr.t("Removing") : Tr.t("Installing"),
                      phone: Tr.t("Now the phone"), remove: Tr.t("Remove Pairlume?"), gone: Tr.t("Pairlume is gone") })[win.step]
            line: ({ lang: Tr.t("Language"), menu: Tr.t("%1 now, this is %2").arg(win.info.installed || "?").arg(win.info.version || "?"),
                     options: Tr.t("You can change it later by running the installer again"),
                     work: "", phone: Tr.t("The app for Android 10 or newer"),
                     remove: Tr.t("The service stops, the windows and menu entries go"), gone: win.forget ? Tr.t("Paired phones are forgotten too") : Tr.t("Paired phones stay remembered") })[win.step]
            lineColor: win.failed && win.step === "work" ? Theme.bad : Theme.dim

            // ---------- the language ----------
            ListView {
                id: langList
                visible: win.step === "lang"
                anchors { fill: parent; leftMargin: 14; rightMargin: 14; topMargin: card.below + 6; bottomMargin: 92 }
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                model: win.langs
                delegate: Choice {
                    required property var modelData
                    width: langList.width
                    label: modelData[1]
                    on: win.lang === modelData[0]
                    onPicked: { win.lang = modelData[0]; Tr.chosen = modelData[0] }
                }
            }

            // ---------- already there: what now ----------
            Column {
                visible: win.step === "menu"
                anchors { left: parent.left; right: parent.right; top: parent.top; topMargin: card.below + 10; leftMargin: 14; rightMargin: 14 }
                Choice { label: Tr.t("Update or repair"); hint: Tr.t("Puts this version in, keeps the paired phones"); go: true; onPicked: win.step = "options" }
                Choice { label: Tr.t("Put the app on the phone"); hint: Tr.t("With a cable, or a code to scan"); go: true; onPicked: win.step = "phone" }
                Choice { label: Tr.t("Remove Pairlume"); hint: Tr.t("You can choose to keep the paired phones"); go: true; onPicked: win.step = "remove" }
            }

            // ---------- options ----------
            Column {
                visible: win.step === "options"
                anchors { left: parent.left; right: parent.right; top: parent.top; topMargin: card.below + 10; leftMargin: 14; rightMargin: 14 }
                Choice { label: Tr.t("Start with my session"); hint: Tr.t("Pairlume's service: always, it is what the phone talks to"); round: false; on: true; enabled: false; opacity: 0.6 }
                Choice { label: Tr.t("Show calls when the phone rings"); hint: Tr.t("The call window starts with the desktop"); round: false; on: win.calls; onPicked: win.calls = !win.calls }
                Choice { label: Tr.t("Add to the menu of applications"); hint: Tr.t("Messages, Settings, Pair a phone"); round: false; on: win.menu; onPicked: win.menu = !win.menu }
                Choice { label: Tr.t("Pair a phone when done"); hint: Tr.t("Opens the pairing window at the end"); round: false; on: win.pairAfter; onPicked: win.pairAfter = !win.pairAfter }
                Item { width: 1; height: 10 }
                // a firewall keeps phones out unless it lets them in; that needs a password, so it is a command to copy
                Text {
                    visible: (win.info.firewall || "") !== ""
                    width: parent.width
                    wrapMode: Text.Wrap
                    textFormat: Text.PlainText
                    text: Tr.t("A firewall is on: let phones in with this command, in a terminal:")
                    color: Theme.dim
                    font.pixelSize: 13
                }
                Item { width: 1; height: 6 }
                Rectangle {
                    visible: (win.info.firewall || "") !== ""
                    width: parent.width
                    height: fw.height + 20
                    radius: 14
                    color: Theme.fade(Theme.text, 0.07)
                    Text { id: fw; x: 12; y: 10; width: parent.width - 90; wrapMode: Text.WrapAnywhere; textFormat: Text.PlainText; text: win.info.firewall || ""; color: Theme.text; font { family: "monospace"; pixelSize: 12 } }
                    Pill { anchors { right: parent.right; rightMargin: 6; verticalCenter: parent.verticalCenter } text: Tr.t("Copy"); onClicked: win.copy(win.info.firewall) }
                }
            }

            // ---------- working ----------
            ListView {
                id: work
                visible: win.step === "work"
                anchors { fill: parent; leftMargin: 26; rightMargin: 26; topMargin: card.below; bottomMargin: 92 }
                clip: true
                model: win.lines
                onCountChanged: positionViewAtEnd()
                delegate: Text {
                    required property string modelData
                    width: work.width
                    wrapMode: Text.Wrap
                    textFormat: Text.PlainText
                    text: modelData.replace(/^• /, "✓  ")
                    color: modelData.startsWith("• ") ? Theme.text : Theme.dim
                    font.pixelSize: 14
                    lineHeight: 1.5
                    opacity: 0
                    Component.onCompleted: opacity = 1
                    Behavior on opacity { NumberAnimation { duration: Theme.quick } }
                }
            }

            // ---------- the phone ----------
            Column {
                visible: win.step === "phone"
                anchors { left: parent.left; right: parent.right; top: parent.top; topMargin: card.below + 4; leftMargin: 26; rightMargin: 26 }
                spacing: 12
                Text {
                    width: parent.width
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.Wrap
                    textFormat: Text.PlainText
                    text: (win.info.phones || []).length > 0 ? Tr.t("%1 is connected by cable.").arg(win.info.phones[0]) : Tr.t("Scan this with the phone's camera to download the app, then open the file to install it:")
                    color: Theme.dim
                    font.pixelSize: 14
                }
                Qr {
                    visible: (win.info.phones || []).length === 0
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: 230
                    height: 230
                    rows: win.info.apk_url ? service.qr(win.info.apk_url) : ""
                }
                Pill {
                    visible: (win.info.phones || []).length > 0
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: win.cabling ? Tr.t("Installing…") : Tr.t("Install over the cable")
                    filled: true
                    enabled: !win.cabling
                    onClicked: { win.cabling = true; win.run(["--phone"]) }
                }
                Text {
                    width: parent.width
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.Wrap
                    textFormat: Text.PlainText
                    visible: win.lines.length > 0 && win.step === "phone"
                    text: win.lines.length > 0 ? win.lines[win.lines.length - 1].replace(/^• /, "") : ""
                    color: Theme.text
                    font.pixelSize: 13
                }
                Text {
                    width: parent.width
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.Wrap
                    textFormat: Text.PlainText
                    text: Tr.t("Or connect it by USB with USB debugging on.")
                    visible: (win.info.phones || []).length === 0
                    color: Theme.dim
                    font.pixelSize: 12
                }
            }

            // ---------- removing ----------
            Column {
                visible: win.step === "remove"
                anchors { left: parent.left; right: parent.right; top: parent.top; topMargin: card.below + 10; leftMargin: 14; rightMargin: 14 }
                Choice { label: Tr.t("Also forget the paired phones"); hint: Tr.t("They would have to pair again"); round: false; on: win.forget; onPicked: win.forget = !win.forget }
            }
            Phone { visible: win.step === "gone"; anchors.centerIn: parent; glow: 0 }

            // ---------- the buttons ----------
            Row {
                anchors { bottom: parent.bottom; bottomMargin: 34; horizontalCenter: parent.horizontalCenter }
                spacing: 12
                Pill { visible: win.step === "menu" || win.step === "options" || win.step === "remove"; text: Tr.t("Back"); onClicked: win.step = win.step === "options" && !win.info.installed ? "lang" : win.step === "menu" ? "lang" : win.info.installed ? "menu" : "lang" }
                Pill { visible: win.step === "lang"; filled: true; text: Tr.t("Next"); onClicked: win.step = win.info.installed ? "menu" : "options" }
                Pill { visible: win.step === "options"; filled: true; text: win.info.installed ? Tr.t("Update") : Tr.t("Install"); enabled: win.info.has_installer === true; onClicked: win.install() }
                Pill { visible: win.step === "remove"; filled: true; text: Tr.t("Remove"); onClicked: win.remove() }
                Pill { visible: win.step === "work" && win.failed; text: Tr.t("Close"); onClicked: Qt.quit() }
                Pill { visible: win.step === "phone"; filled: !win.pairAfter; text: Tr.t("Done"); onClicked: Qt.quit() }
                Pill { visible: win.step === "phone" && win.pairAfter && !win.removing; filled: true; text: Tr.t("Pair a phone"); onClicked: { service.open(JSON.stringify([])); Qt.quit() } }
                Pill { visible: win.step === "gone"; filled: true; text: Tr.t("Close"); onClicked: Qt.quit() }
            }
        }
    }
    Shots { of: scene; what: "setup-" + win.step + (win.failed ? "-failed" : "") }
}
