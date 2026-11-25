// SPDX-License-Identifier: GPL-3.0-or-later
pragma Singleton
import QtQuick
import dev.pairlume

// The words of the windows, from share/lang/<code>.json. English is in the code and is the key; a word that is not
// translated stays English. The language is the one chosen in the settings, else the system's; --lang for pictures.
QtObject {
    id: tr
    property Service s: Service {}
    property string chosen: s.chosenLanguage()
    readonly property string lang: {
        const a = Qt.application.arguments, i = a.indexOf("--lang")
        if (i > 0) return a[i + 1]
        return chosen !== "" ? chosen : Qt.locale().name.slice(0, 2)
    }
    readonly property var words: { try { return JSON.parse(s.words(lang)) } catch (e) { return {} } }
    function t(x) { return words[x] || x }
    // another window may choose another language: all of them follow (not the installer, which chooses its own)
    property bool pinned: false
    // how the phone's notifications look: "card" at the top right, or "banner" at the top like texts on an iPhone
    property string notifStyle: tr.s.uiValue("notif_style") || "card"
    property Timer look: Timer {
        interval: 1500; repeat: true; running: !tr.pinned
        onTriggered: {
            const c = tr.s.chosenLanguage(); if (c !== tr.chosen) tr.chosen = c
            const n = tr.s.uiValue("notif_style") || "card"; if (n !== tr.notifStyle) tr.notifStyle = n
        }
    }
}
