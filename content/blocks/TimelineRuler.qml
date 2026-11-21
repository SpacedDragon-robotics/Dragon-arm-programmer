// TimelineRuler.qml -- seconds scale above the tracks.

import QtQuick
import DragonArm

Item {
    id: ruler

    property real pixelsPerSecond: 72
    property real span: 20

    // Major tick interval, chosen so labels stay roughly 70 px apart.
    readonly property real majorStep: {
        var candidates = [0.1, 0.25, 0.5, 1, 2, 5, 10, 15, 30, 60, 120]
        for (var i = 0; i < candidates.length; ++i) {
            if (candidates[i] * pixelsPerSecond >= 66)
                return candidates[i]
        }
        return candidates[candidates.length - 1]
    }

    height: 28

    Rectangle {
        anchors.fill: parent
        color: Theme.surfaceAlt
    }

    Canvas {
        id: canvas
        anchors.fill: parent

        onWidthChanged: requestPaint()
        onHeightChanged: requestPaint()

        Connections {
            target: ruler
            function onPixelsPerSecondChanged() { canvas.requestPaint() }
            function onSpanChanged() { canvas.requestPaint() }
        }

        onPaint: {
            var ctx = getContext("2d")
            ctx.reset()
            ctx.font = "10px " + Theme.monoFamily
            ctx.textBaseline = "alphabetic"

            var major = ruler.majorStep
            var minor = major / 5
            var pps = ruler.pixelsPerSecond

            // Minor ticks
            ctx.strokeStyle = Theme.border
            ctx.lineWidth = 1
            for (var t = 0; t <= ruler.span + minor; t += minor) {
                var x = Math.round(t * pps) + 0.5
                if (x > width)
                    break
                ctx.beginPath()
                ctx.moveTo(x, height - 6)
                ctx.lineTo(x, height)
                ctx.stroke()
            }

            // Major ticks + labels
            ctx.strokeStyle = Theme.borderStrong
            ctx.fillStyle = Theme.textSecondary
            for (t = 0; t <= ruler.span + major; t += major) {
                x = Math.round(t * pps) + 0.5
                if (x > width)
                    break
                ctx.beginPath()
                ctx.moveTo(x, height - 12)
                ctx.lineTo(x, height)
                ctx.stroke()

                var label = major < 1 ? t.toFixed(2) + "s" : t.toFixed(0) + "s"
                ctx.fillText(label, x + 4, 13)
            }

            // Baseline
            ctx.strokeStyle = Theme.border
            ctx.beginPath()
            ctx.moveTo(0, height - 0.5)
            ctx.lineTo(width, height - 0.5)
            ctx.stroke()
        }
    }
}
