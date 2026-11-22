// SPDX-License-Identifier: GPL-3.0-or-later
import QtQuick
import QtQuick.Shapes
import dev.pairlume

Rectangle {
    id: card
    required property Service service
    // looking | asking | paired | failed | gone (the service is not there)
    property string step: "gone"
    property string how: "shake"
    property string digits
    property string qr
    property string name
    property string code
    property string why
    property int total: 120
    property real remaining: 0
    property bool answered: false
    signal closed

    function send(r) { service.ask(JSON.stringify(r)) }
    function begin() { why = ""; code = ""; answered = false; send({ cmd: "pair" }) }
    function stop() { if (step === "looking" || step === "asking") send({ cmd: "cancel_pairing" }) }
    function answer(yes) { if (answered) return; answered = true; send({ cmd: "answer", yes: yes }) }
    function happened(e) {
        switch (e.event) {
        case "pairing_open":
            digits = e.digits; qr = service.qr(e.qr || ""); total = e.seconds; remaining = e.seconds
            if (qr === "" && how === "qr") how = "shake"
            step = "looking"
            break
        case "pairing_code": name = e.name; code = e.code; answered = false; step = "asking"; break
        case "paired": name = e.name; step = "paired"; break
        case "pairing_closed": if (step === "looking" || step === "asking") {
                why = ({ expired: qsTr("No phone in two minutes"), stopped: qsTr("Pairing was stopped"),
                         failed: qsTr("The codes were not the same, or the phone went away") })[e.reason] || ""
                step = "failed"; nope.restart()
            }
            break
        }
    }

    width: 420
    height: 560
    radius: 32
    color: Theme.fade(Theme.surface, Theme.glass)
    border.color: Theme.fade(Theme.text, 0.12)
    // the light on the upper edge of the glass
    Rectangle {
        anchors { fill: parent; margins: 1 }
        radius: 31
        gradient: Gradient {
            GradientStop { position: 0; color: Theme.fade(Theme.text, 0.08) }
            GradientStop { position: 0.3; color: "transparent" }
        }
    }
    Connections {
        target: card.service
        function onConnectedChanged() { if (card.service.connected) card.begin(); else card.step = "gone" }
        function onHappened(json) { card.happened(JSON.parse(json)) }
        function onFailed(why) { if (card.step !== "paired") { card.why = why; card.step = "failed" } }
    }
    Timer { interval: 250; repeat: true; running: card.step === "looking"; onTriggered: card.remaining = Math.max(0, card.remaining - 0.25) }
    Timer { interval: 2600; running: card.step === "paired"; onTriggered: card.closed() }
    SequentialAnimation {
        id: nope
        NumberAnimation { target: shift; property: "x"; to: -12; duration: 60 }
        NumberAnimation { target: shift; property: "x"; to: 10; duration: 90 }
        NumberAnimation { target: shift; property: "x"; to: -6; duration: 80 }
        NumberAnimation { target: shift; property: "x"; to: 0; duration: 120; easing.type: Easing.OutQuad }
    }
    transform: Translate { id: shift }

    Text {
        id: title
        anchors { top: parent.top; topMargin: 34; horizontalCenter: parent.horizontalCenter }
        text: ({ looking: card.how === "shake" ? qsTr("Shake your phone") : card.how === "qr" ? qsTr("Scan with your phone") : qsTr("Type this on your phone"),
                 asking: card.name, paired: qsTr("Connected"), failed: qsTr("That did not work"), gone: qsTr("Pairlume is not running") })[card.step]
        textFormat: Text.PlainText
        width: parent.width - 60
        horizontalAlignment: Text.AlignHCenter
        elide: Text.ElideRight
        color: Theme.text
        font.pixelSize: 25
        font.weight: Font.Bold
        Behavior on text { SequentialAnimation {
            NumberAnimation { target: title; property: "opacity"; to: 0; duration: 110 }
            PropertyAction {}
            NumberAnimation { target: title; property: "opacity"; to: 1; duration: 200 }
        } }
    }
    Text {
        anchors { top: title.bottom; topMargin: 8; horizontalCenter: parent.horizontalCenter }
        width: parent.width - 70
        horizontalAlignment: Text.AlignHCenter
        wrapMode: Text.WordWrap
        maximumLineCount: 3
        elide: Text.ElideRight
        textFormat: Text.PlainText
        text: ({ looking: qsTr("with Pairlume open, on the same Wi-Fi"), asking: qsTr("Is the same code on its screen?"), paired: card.name,
                 failed: card.why, gone: qsTr("Start pairlumed, this window will notice") })[card.step]
        color: card.step === "failed" ? Theme.bad : Theme.dim
        font.pixelSize: 14
    }

    Item {
        id: stage
        anchors { horizontalCenter: parent.horizontalCenter; top: parent.top; topMargin: 128 }
        width: 300
        height: 300
        Rings { anchors.fill: parent; on: card.step === "looking" && card.how === "shake" }
        // the time that is left
        Shape {
            anchors.centerIn: parent
            width: 288
            height: 288
            preferredRendererType: Shape.CurveRenderer
            opacity: card.step === "looking" && card.how === "shake" ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: Theme.normal } }
            ShapePath {
                strokeWidth: 4
                strokeColor: Theme.fade(Theme.accent, 0.55)
                fillColor: "transparent"
                capStyle: ShapePath.RoundCap
                PathAngleArc { centerX: 144; centerY: 144; radiusX: 140; radiusY: 140; startAngle: -90; sweepAngle: 360 * card.remaining / card.total }
            }
        }
        // the light when both are one
        Rectangle {
            id: light
            property bool on: card.step === "paired"
            anchors.centerIn: parent
            width: 300
            height: 300
            radius: 150
            gradient: Gradient {
                GradientStop { position: 0; color: Theme.fade(Theme.accent2, 0.75) }
                GradientStop { position: 1; color: Theme.fade(Theme.accent, 0.75) }
            }
            opacity: on ? 1 : 0
            scale: on ? 0.62 : 0.1
            Behavior on scale { NumberAnimation { duration: Theme.slow; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.spring } }
            Behavior on opacity { NumberAnimation { duration: Theme.normal } }
        }
        Shape {
            id: tick
            anchors.centerIn: parent
            width: 120
            height: 120
            preferredRendererType: Shape.CurveRenderer
            opacity: card.step === "paired" ? 1 : 0
            property real t: card.step === "paired" ? 1 : 0
            // the short stroke, then the long one
            readonly property real a: Math.min(1, t / 0.4)
            readonly property real b: Math.max(0, (t - 0.4) / 0.6)
            Behavior on t { SequentialAnimation { PauseAnimation { duration: 320 } NumberAnimation { duration: 420; easing.type: Easing.OutCubic } } }
            ShapePath {
                strokeWidth: 12
                strokeColor: Theme.ink
                fillColor: "transparent"
                capStyle: ShapePath.RoundCap
                joinStyle: ShapePath.RoundJoin
                startX: 30; startY: 62
                PathLine { x: 30 + 22 * tick.a; y: 62 + 22 * tick.a }
                PathLine { x: 30 + 22 * tick.a + 40 * tick.b; y: 62 + 22 * tick.a - 46 * tick.b }
            }
        }
        Phone {
            id: phone
            waving: card.step === "looking"
            glow: card.step === "asking" ? 1 : 0
            Behavior on glow { NumberAnimation { duration: Theme.normal } }
            anchors.horizontalCenter: parent.horizontalCenter
            y: card.step === "asking" ? 6 : 88
            scale: card.step === "paired" || card.step === "gone" ? 0.2 : (card.step === "asking" ? 0.86 : 1)
            opacity: card.step === "paired" || card.step === "gone" ? 0 : (card.step === "looking" && card.how !== "shake" ? 0 : 1)
            Behavior on y { NumberAnimation { duration: Theme.slow; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.spring } }
            Behavior on scale { NumberAnimation { duration: Theme.normal; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.smooth } }
            Behavior on opacity { NumberAnimation { duration: Theme.quick } }
        }
        Loader {
            anchors { horizontalCenter: parent.horizontalCenter; bottom: parent.bottom; bottomMargin: 62 }
            active: card.step === "asking"
            sourceComponent: Digits { code: card.code }
        }
        Loader {
            anchors.centerIn: parent
            active: card.step === "looking" && card.how === "digits"
            sourceComponent: Digits { code: card.digits }
        }
        Qr {
            anchors.centerIn: parent
            width: 268
            height: 268
            rows: card.qr
            opacity: card.step === "looking" && card.how === "qr" ? 1 : 0
            visible: opacity > 0
            scale: card.how === "qr" ? 1 : 0.8
            Behavior on opacity { NumberAnimation { duration: Theme.quick } }
            Behavior on scale { NumberAnimation { duration: Theme.normal; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.spring } }
        }
    }

    Row {
        anchors { bottom: parent.bottom; bottomMargin: 34; horizontalCenter: parent.horizontalCenter }
        spacing: 10
        visible: card.step === "looking"
        Pill { text: qsTr("Shake"); chosen: card.how === "shake"; onClicked: card.how = "shake" }
        Pill { text: qsTr("QR code"); chosen: card.how === "qr"; enabled: card.qr !== ""; onClicked: card.how = "qr" }
        Pill { text: qsTr("Digits"); chosen: card.how === "digits"; onClicked: card.how = "digits" }
    }
    Row {
        anchors { bottom: parent.bottom; bottomMargin: 34; horizontalCenter: parent.horizontalCenter }
        spacing: 12
        visible: card.step === "asking"
        // not under a finger that was already on its way somewhere else
        property bool ready: false
        onVisibleChanged: { ready = false; if (visible) wait.restart() }
        Timer { id: wait; interval: 900; onTriggered: parent.ready = true }
        Pill { text: qsTr("Not the same"); enabled: parent.ready && !card.answered; onClicked: card.answer(false) }
        Pill { text: qsTr("They match"); filled: true; enabled: parent.ready && !card.answered; onClicked: card.answer(true) }
    }
    Row {
        anchors { bottom: parent.bottom; bottomMargin: 34; horizontalCenter: parent.horizontalCenter }
        spacing: 12
        visible: card.step === "failed"
        Pill { text: qsTr("Close"); onClicked: card.closed() }
        Pill { text: qsTr("Try again"); filled: true; onClicked: card.begin() }
    }
    Pill {
        anchors { bottom: parent.bottom; bottomMargin: 34; horizontalCenter: parent.horizontalCenter }
        visible: card.step === "gone"
        text: qsTr("Close")
        onClicked: card.closed()
    }
}
