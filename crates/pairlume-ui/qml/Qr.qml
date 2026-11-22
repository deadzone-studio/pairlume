// SPDX-License-Identifier: GPL-3.0-or-later
import QtQuick
import dev.pairlume

// Always dark on white with a quiet edge: cameras have to read it in every theme.
Rectangle {
    id: q
    property string rows
    readonly property var lines: rows === "" ? [] : rows.split("\n")
    radius: 20
    color: "white"
    Accessible.role: Accessible.Graphic
    Accessible.name: Tr.t("QR code for pairing")
    onRowsChanged: cv.requestPaint()
    Canvas {
        id: cv
        anchors { fill: parent; margins: 18 }
        onPaint: {
            const c = getContext("2d"), n = q.lines.length
            c.reset()
            if (n === 0) return
            const s = Math.floor(width / n), off = Math.floor((width - s * n) / 2)
            c.fillStyle = "#0b1020"
            for (let y = 0; y < n; y++) for (let x = 0; x < n; x++)
                if (q.lines[y][x] === "1") c.fillRect(off + x * s, off + y * s, s, s)
        }
    }
}
