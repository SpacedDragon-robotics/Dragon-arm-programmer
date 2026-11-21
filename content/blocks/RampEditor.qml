// RampEditor.qml
//
// Acceleration ramp as a speed-over-time graph you can grab.
//
// The shape IS the setting: drag either shoulder of the S-curve inwards to
// accelerate harder over less time, outwards to ease in and out. A stepper
// that is asked to reach full speed instantly stalls, so the ramp is the
// difference between a movement that works and one that loses steps.

import QtQuick
import DragonArm
import "../common"

Item {
    id: editor

    property real ramp: 0.25
    property color accent: Theme.accent

    // Live feedback from the plan, so the graph can go red before the
    // validator has to complain.
    property real peakSpeed: 0
    property real peakAccel: 0
    property real maxSpeed: 0
    property real maxAccel: 0
    property string unit: "°/s"

    readonly property bool speedExceeded: maxSpeed > 0 && peakSpeed > maxSpeed + 1e-6
    readonly property bool accelExceeded: maxAccel > 0 && peakAccel > maxAccel + 1e-6
    readonly property bool overLimit: speedExceeded || accelExceeded
    readonly property color toneColor: overLimit ? Theme.danger : accent

    signal moved(real newRamp)

    implicitHeight: 150

    function clampRamp(v) {
        return Math.max(0, Math.min(0.5, v))
    }

    // ---- Header ---------------------------------------------------------
    Text {
        id: caption
        anchors.left: parent.left
        anchors.top: parent.top
        text: "RAMP"
        color: Theme.textSecondary
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontTiny
        font.weight: Theme.weightStrong
        font.letterSpacing: 0.5
    }

    Text {
        anchors.left: caption.right
        anchors.leftMargin: Theme.spacingSmall
        anchors.baseline: caption.baseline
        text: editor.ramp <= 0.001
              ? "no ramp – instant start"
              : (editor.ramp >= 0.499
                 ? "full – always accelerating"
                 : Math.round(editor.ramp * 100) + "% in, " + Math.round(editor.ramp * 100)
                   + "% out")
        color: editor.ramp <= 0.001 ? Theme.danger : Theme.textMuted
        font.family: Theme.fontFamily
        font.weight: Theme.weightBody
        font.pixelSize: Theme.fontTiny
    }

    // ---- Presets --------------------------------------------------------
    Row {
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.topMargin: -3
        spacing: 3

        Repeater {
            model: [
                { label: "Soft", value: 0.45 },
                { label: "Normal", value: 0.25 },
                { label: "Sharp", value: 0.08 }
            ]

            delegate: Rectangle {
                id: preset
                required property var modelData

                readonly property bool active:
                    Math.abs(editor.ramp - preset.modelData.value) < 0.005

                width: 46
                height: 19
                radius: Theme.radiusSmall
                color: active ? Theme.accentSoft
                              : (presetMouse.containsMouse ? Theme.surfaceHover : Theme.surfaceAlt)
                border.width: 1
                border.color: active ? editor.accent : Theme.border

                Text {
                    anchors.centerIn: parent
                    text: preset.modelData.label
                    color: preset.active ? Theme.accentBright : Theme.textMuted
                    font.family: Theme.fontFamily
                    font.weight: Theme.weightBody
                    font.pixelSize: Theme.fontTiny
                }

                MouseArea {
                    id: presetMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: editor.moved(preset.modelData.value)
                }
            }
        }
    }

    // ---- Graph ----------------------------------------------------------
    Rectangle {
        id: plot

        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: caption.bottom
        anchors.topMargin: 6
        height: 78
        radius: Theme.radiusSmall
        color: Theme.surfaceAlt
        border.width: 1
        border.color: editor.overLimit ? Theme.danger : Theme.border

        readonly property real plotLeft: 10
        readonly property real plotRight: width - 10
        readonly property real plotTop: 12
        readonly property real plotBottom: height - 16
        readonly property real plotWidth: plotRight - plotLeft

        function xForRamp(r) {
            return plotLeft + plotWidth * r
        }

        Canvas {
            id: canvas
            anchors.fill: parent

            onWidthChanged: requestPaint()
            onHeightChanged: requestPaint()

            Connections {
                target: editor
                function onRampChanged() { canvas.requestPaint() }
                function onToneColorChanged() { canvas.requestPaint() }
            }

            onPaint: {
                var ctx = getContext("2d")
                ctx.reset()

                var l = plot.plotLeft, r = plot.plotRight
                var top = plot.plotTop, bot = plot.plotBottom
                var ramp = editor.clampRamp(editor.ramp)

                // Baseline
                ctx.strokeStyle = Theme.border
                ctx.lineWidth = 1
                ctx.beginPath()
                ctx.moveTo(l, bot + 0.5)
                ctx.lineTo(r, bot + 0.5)
                ctx.stroke()

                var x1 = plot.xForRamp(ramp)
                var x2 = plot.xForRamp(1 - ramp)

                // A wider ramp means a higher peak to cover the same distance,
                // so the shape gets taller as it narrows. The curve is sampled
                // from the plan's own profile function, so the editor shows
                // exactly the S-curve the arm will run, not a sketch of it.
                var peakRatio = 1.0 / (1.0 - ramp)      // 1.0 .. 2.0
                var scaleY = (bot - top) / 2.0           // peak of 2.0 fills the plot
                var peakY = bot - scaleY * peakRatio

                var samples = 96
                ctx.beginPath()
                ctx.moveTo(l, bot)
                for (var i = 1; i < samples; ++i) {
                    var p = i / samples
                    var v = MovementPlan.profileVelocity(p, ramp)
                    ctx.lineTo(l + (r - l) * p, bot - scaleY * v)
                }
                ctx.lineTo(r, bot)
                ctx.closePath()

                ctx.fillStyle = Theme.fade(editor.toneColor, 0.22)
                ctx.fill()
                ctx.strokeStyle = editor.toneColor
                ctx.lineWidth = 2
                ctx.stroke()

                // Shoulder guides
                ctx.strokeStyle = Theme.fade(editor.toneColor, 0.5)
                ctx.lineWidth = 1
                ctx.setLineDash([3, 3])
                ctx.beginPath()
                ctx.moveTo(x1, peakY); ctx.lineTo(x1, bot)
                ctx.moveTo(x2, peakY); ctx.lineTo(x2, bot)
                ctx.stroke()
                ctx.setLineDash([])

                // Labels
                ctx.fillStyle = Theme.textMuted
                // Multi-word families must be quoted in the CSS font shorthand.
                ctx.font = "9px \"" + Theme.fontFamily + "\""
                ctx.fillText("speed", l, top - 2)
                ctx.textAlign = "right"
                ctx.fillText("time", r, bot + 12)
            }
        }

        // Grab handles on both shoulders.
        Repeater {
            model: 2

            delegate: Rectangle {
                required property int index

                readonly property real handleX: index === 0
                    ? plot.xForRamp(editor.clampRamp(editor.ramp))
                    : plot.xForRamp(1 - editor.clampRamp(editor.ramp))

                x: handleX - width / 2
                y: plot.plotBottom - 4
                width: 11
                height: 11
                radius: Theme.radiusSmall
                color: dragArea.pressed ? Theme.surfaceHover : Theme.textPrimary
                border.width: 2
                border.color: editor.toneColor
            }
        }

        MouseArea {
            id: dragArea
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.SizeHorCursor

            function applyFrom(mouseX) {
                var rel = (mouseX - plot.plotLeft) / Math.max(plot.plotWidth, 1)
                // Grab whichever shoulder is nearer, so both sides feel alive.
                var r = rel > 0.5 ? (1 - rel) : rel
                editor.moved(editor.clampRamp(r))
            }

            onPressed: function (mouseEvent) { applyFrom(mouseEvent.x) }
            onPositionChanged: function (mouseEvent) {
                if (pressed)
                    applyFrom(mouseEvent.x)
            }
        }
    }

    // ---- Readout --------------------------------------------------------
    Row {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: plot.bottom
        anchors.topMargin: 6
        spacing: Theme.spacing

        Text {
            text: "peak " + editor.peakSpeed.toFixed(1) + editor.unit
                  + (editor.maxSpeed > 0 ? "  /  max " + editor.maxSpeed.toFixed(0)
                                           + editor.unit : "")
            color: editor.speedExceeded ? Theme.danger : Theme.textMuted
            font.family: Theme.monoFamily
            font.pixelSize: Theme.fontTiny
            font.bold: editor.speedExceeded
        }

        Text {
            visible: editor.maxAccel > 0
            text: "accel " + (isFinite(editor.peakAccel)
                              ? editor.peakAccel.toFixed(0) : "∞")
                  + "  /  max " + editor.maxAccel.toFixed(0)
            color: editor.accelExceeded ? Theme.danger : Theme.textMuted
            font.family: Theme.monoFamily
            font.pixelSize: Theme.fontTiny
            font.bold: editor.accelExceeded
        }
    }
}
