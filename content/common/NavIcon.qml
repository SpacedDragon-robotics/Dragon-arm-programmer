// NavIcon.qml -- small stroked icons, drawn so the app needs no icon font.
//
// Galaxy theme: straight edges only -- miter joins, square caps, squares and
// diamonds instead of circles -- so the icons match the sharp corners.

import QtQuick
import DragonArm

Canvas {
    id: icon

    // "home" | "blocks" | "code" | "robot" | "trash" | "chevronLeft" | "chevronRight"
    // | "cube" | "play" | "pause" | "restart" | "loop" | "star"
    property string name: "home"
    property color color: Theme.textSecondary
    property real thickness: 1.6

    width: 22
    height: 22
    antialiasing: true

    onNameChanged: requestPaint()
    onColorChanged: requestPaint()
    onWidthChanged: requestPaint()
    onHeightChanged: requestPaint()
    onThicknessChanged: requestPaint()

    onPaint: {
        var ctx = getContext("2d")
        ctx.reset()
        ctx.strokeStyle = icon.color
        ctx.fillStyle = icon.color
        ctx.lineWidth = icon.thickness
        ctx.lineCap = "square"
        ctx.lineJoin = "miter"
        ctx.miterLimit = 4

        // Everything is drawn in a 22x22 box and scaled to the real size.
        var s = Math.min(width, height) / 22
        ctx.scale(s, s)

        function diamond(cx, cy, r) {
            ctx.beginPath()
            ctx.moveTo(cx, cy - r)
            ctx.lineTo(cx + r, cy)
            ctx.lineTo(cx, cy + r)
            ctx.lineTo(cx - r, cy)
            ctx.closePath()
        }

        switch (name) {
        case "home":
            // Flat-roofed house outline with a door: one path.
            ctx.beginPath()
            ctx.moveTo(3, 10)
            ctx.lineTo(11, 3.5)
            ctx.lineTo(19, 10)
            ctx.lineTo(19, 19)
            ctx.lineTo(13.5, 19)
            ctx.lineTo(13.5, 13.5)
            ctx.lineTo(8.5, 13.5)
            ctx.lineTo(8.5, 19)
            ctx.lineTo(3, 19)
            ctx.closePath()
            ctx.stroke()
            break

        case "blocks":
            // A 2x2 grid of squares.
            ctx.beginPath()
            ctx.rect(3, 3, 6.5, 6.5)
            ctx.rect(12.5, 3, 6.5, 6.5)
            ctx.rect(3, 12.5, 6.5, 6.5)
            ctx.rect(12.5, 12.5, 6.5, 6.5)
            ctx.stroke()
            break

        case "code":
            ctx.beginPath()
            ctx.moveTo(8, 6)
            ctx.lineTo(3.5, 11)
            ctx.lineTo(8, 16)
            ctx.stroke()
            ctx.beginPath()
            ctx.moveTo(14, 6)
            ctx.lineTo(18.5, 11)
            ctx.lineTo(14, 16)
            ctx.stroke()
            ctx.beginPath()
            ctx.moveTo(12.3, 4.5)
            ctx.lineTo(9.7, 17.5)
            ctx.stroke()
            break

        case "robot":
            // Stylised arm: base, two links, joints as diamonds, gripper.
            ctx.beginPath()
            ctx.moveTo(3, 19)
            ctx.lineTo(10, 19)
            ctx.stroke()
            ctx.beginPath()
            ctx.moveTo(6.5, 19)
            ctx.lineTo(6.5, 13.5)
            ctx.moveTo(7.8, 11.2)
            ctx.lineTo(11.8, 8.8)
            ctx.moveTo(14.2, 8.8)
            ctx.lineTo(17.5, 11)
            ctx.stroke()
            diamond(6.5, 12, 1.7)
            ctx.stroke()
            diamond(13, 8, 1.7)
            ctx.stroke()
            ctx.beginPath()
            ctx.moveTo(17.5, 11)
            ctx.lineTo(19.5, 10)
            ctx.moveTo(17.5, 11)
            ctx.lineTo(18.5, 13)
            ctx.stroke()
            break

        case "trash":
            ctx.beginPath()
            ctx.moveTo(4, 6.5)
            ctx.lineTo(18, 6.5)
            ctx.stroke()
            ctx.beginPath()
            ctx.moveTo(8.5, 6.5)
            ctx.lineTo(8.5, 4)
            ctx.lineTo(13.5, 4)
            ctx.lineTo(13.5, 6.5)
            ctx.stroke()
            ctx.beginPath()
            ctx.moveTo(6, 6.5)
            ctx.lineTo(6, 19)
            ctx.lineTo(16, 19)
            ctx.lineTo(16, 6.5)
            ctx.stroke()
            ctx.beginPath()
            ctx.moveTo(9.5, 10)
            ctx.lineTo(9.5, 15.5)
            ctx.moveTo(12.5, 10)
            ctx.lineTo(12.5, 15.5)
            ctx.stroke()
            break

        case "chevronLeft":
            ctx.beginPath()
            ctx.moveTo(13.5, 4.5)
            ctx.lineTo(7, 11)
            ctx.lineTo(13.5, 17.5)
            ctx.stroke()
            break

        case "chevronRight":
            ctx.beginPath()
            ctx.moveTo(8.5, 4.5)
            ctx.lineTo(15, 11)
            ctx.lineTo(8.5, 17.5)
            ctx.stroke()
            break

        case "cube":
            // Isometric box: top face, then the two visible sides.
            ctx.beginPath()
            ctx.moveTo(11, 2.5)
            ctx.lineTo(18.5, 6.5)
            ctx.lineTo(11, 10.5)
            ctx.lineTo(3.5, 6.5)
            ctx.closePath()
            ctx.stroke()
            ctx.beginPath()
            ctx.moveTo(3.5, 6.5)
            ctx.lineTo(3.5, 15.5)
            ctx.lineTo(11, 19.5)
            ctx.lineTo(18.5, 15.5)
            ctx.lineTo(18.5, 6.5)
            ctx.stroke()
            ctx.beginPath()
            ctx.moveTo(11, 10.5)
            ctx.lineTo(11, 19.5)
            ctx.stroke()
            break

        case "play":
            ctx.beginPath()
            ctx.moveTo(7, 4.5)
            ctx.lineTo(17.5, 11)
            ctx.lineTo(7, 17.5)
            ctx.closePath()
            ctx.fill()
            break

        case "pause":
            ctx.beginPath()
            ctx.rect(5.5, 4.5, 4, 13)
            ctx.rect(12.5, 4.5, 4, 13)
            ctx.fill()
            break

        case "restart":
            // Bar plus a left-pointing triangle: "back to the start".
            ctx.beginPath()
            ctx.rect(4.5, 5, 2.5, 12)
            ctx.fill()
            ctx.beginPath()
            ctx.moveTo(17.5, 5)
            ctx.lineTo(8.5, 11)
            ctx.lineTo(17.5, 17)
            ctx.closePath()
            ctx.fill()
            break

        case "loop":
            // A square loop with an arrowhead, no curves.
            ctx.beginPath()
            ctx.moveTo(15, 5.5)
            ctx.lineTo(18, 5.5)
            ctx.lineTo(18, 16.5)
            ctx.lineTo(4, 16.5)
            ctx.lineTo(4, 5.5)
            ctx.lineTo(11, 5.5)
            ctx.stroke()
            ctx.beginPath()
            ctx.moveTo(9, 2.5)
            ctx.lineTo(12, 5.5)
            ctx.lineTo(9, 8.5)
            ctx.stroke()
            break

        case "star":
            // The theme's sharp 4-point star.
            ctx.beginPath()
            ctx.moveTo(11, 2)
            ctx.lineTo(12.7, 9.3)
            ctx.lineTo(20, 11)
            ctx.lineTo(12.7, 12.7)
            ctx.lineTo(11, 20)
            ctx.lineTo(9.3, 12.7)
            ctx.lineTo(2, 11)
            ctx.lineTo(9.3, 9.3)
            ctx.closePath()
            ctx.fill()
            break
        }
    }
}
