// JointConfigRow.qml -- one joint's hardware configuration.
//
// Shows the fields that belong to this robot's drive type: PCA9685 channel and
// pulse calibration for servo arms, STEP/DIR pins, gearing, speed limits and
// encoder settings for stepper arms.
//
// Every field reads through num()/flag()/str(). QML evaluates bindings even
// inside items that are hidden, so reading a servo-only property on a stepper
// joint (or the reverse) would spray "cannot assign undefined" warnings. The
// accessors make a missing field a harmless default instead.

import QtQuick
import DragonArm
import "../common"

Rectangle {
    id: row

    property var joint: null

    readonly property bool stepper: RobotLibrary.isStepper
    readonly property bool gripper: !!joint && joint.role === "gripper"

    function num(key, fallback) {
        return (joint && joint[key] !== undefined && joint[key] !== null)
                ? joint[key] : fallback
    }

    function str(key, fallback) {
        return (joint && joint[key] !== undefined && joint[key] !== null)
                ? String(joint[key]) : fallback
    }

    function flag(key) {
        return !!(joint && joint[key])
    }

    function set(key, value) {
        if (joint)
            RobotLibrary.setJointProperty(joint.id, key, value)
    }

    readonly property string clash: {
        if (!joint)
            return ""
        if (stepper) {
            var onStep = RobotLibrary.pinInUse(num("stepPin", -1), joint.id)
            if (onStep.length > 0)
                return onStep
            return RobotLibrary.pinInUse(num("dirPin", -1), joint.id)
        }
        return RobotLibrary.channelInUse(num("channel", -1), joint.id)
    }

    width: parent ? parent.width : 0
    implicitHeight: content.implicitHeight + 2 * Theme.spacing
    height: implicitHeight
    radius: Theme.radiusSmall
    color: Theme.surfaceAlt
    border.width: 1
    border.color: clash.length > 0 ? Theme.danger : Theme.border

    Rectangle {
        anchors.left: parent.left
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        anchors.margins: 1
        width: 3
        radius: Theme.radiusSmall
        color: row.joint ? row.joint.accent : Theme.accent
    }

    Column {
        id: content
        anchors.fill: parent
        anchors.margins: Theme.spacing
        anchors.leftMargin: Theme.spacing + 4
        spacing: Theme.spacingSmall

        // ---- Title ------------------------------------------------------
        Row {
            spacing: Theme.spacingSmall

            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: row.str("name", "")
                color: Theme.textPrimary
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontBody
                font.weight: Theme.weightStrong
            }

            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: "· " + row.str("subtitle", "")
                color: Theme.textMuted
                font.family: Theme.fontFamily
                font.weight: Theme.weightBody
                font.pixelSize: Theme.fontTiny
            }

            Text {
                anchors.verticalCenter: parent.verticalCenter
                visible: row.stepper
                text: row.num("gearRatio", 1) + ":1 · "
                      + row.num("stepsPerDegree", 0).toFixed(3) + " steps/°"
                color: Theme.textMuted
                font.family: Theme.monoFamily
                font.pixelSize: Theme.fontTiny
            }

            Text {
                anchors.verticalCenter: parent.verticalCenter
                visible: row.clash.length > 0
                text: (row.stepper ? "⚠ pin also used by "
                                   : "⚠ channel also used by ") + row.clash
                color: Theme.danger
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontTiny
                font.weight: Theme.weightStrong
            }
        }

        // ---- Stepper: wiring, travel and motion limits -------------------
        Flow {
            width: parent.width
            spacing: Theme.spacing
            visible: row.stepper

            NumberField {
                label: "STEP pin"
                fieldWidth: 58
                value: row.num("stepPin", 0)
                from: 0; to: 19
                warn: row.clash.length > 0
                onCommitted: function (v) { row.set("stepPin", Math.round(v)) }
            }

            NumberField {
                label: "DIR pin"
                fieldWidth: 58
                value: row.num("dirPin", 0)
                from: 0; to: 19
                warn: row.clash.length > 0
                onCommitted: function (v) { row.set("dirPin", Math.round(v)) }
            }

            NumberField {
                label: "Gear ratio"
                fieldWidth: 58
                decimals: 2
                value: row.num("gearRatio", 1)
                from: 0.1; to: 200
                onCommitted: function (v) { row.set("gearRatio", v) }
            }

            NumberField {
                label: "Limit min"
                fieldWidth: 62
                suffix: "°"
                value: row.num("mechMin", 0)
                from: -720; to: 720
                onCommitted: function (v) { row.set("mechMin", v) }
            }

            NumberField {
                label: "Limit max"
                fieldWidth: 62
                suffix: "°"
                value: row.num("mechMax", 180)
                from: -720; to: 720
                onCommitted: function (v) { row.set("mechMax", v) }
            }

            NumberField {
                label: "Max speed"
                fieldWidth: 68
                suffix: "°/s"
                value: row.num("maxSpeedDegPerSec", 60)
                from: 1; to: 2000
                onCommitted: function (v) { row.set("maxSpeedDegPerSec", v) }
            }

            NumberField {
                label: "Max accel"
                fieldWidth: 74
                suffix: "°/s²"
                value: row.num("maxAccelDegPerSec2", 120)
                from: 1; to: 20000
                onCommitted: function (v) { row.set("maxAccelDegPerSec2", v) }
            }
        }

        // ---- Stepper: encoder -------------------------------------------
        Flow {
            width: parent.width
            spacing: Theme.spacing
            visible: row.stepper

            Item {
                width: 64
                height: 42

                Text {
                    anchors.top: parent.top
                    text: "Encoder"
                    color: Theme.textMuted
                    font.family: Theme.fontFamily
                    font.weight: Theme.weightBody
                    font.pixelSize: Theme.fontTiny
                }

                Text {
                    anchors.bottom: parent.bottom
                    anchors.bottomMargin: 5
                    text: row.str("encoderPin", "–")
                    color: Theme.textPrimary
                    font.family: Theme.monoFamily
                    font.pixelSize: Theme.fontBody
                }
            }

            NumberField {
                // Negative is fine: the sketch subtracts the offset and then
                // folds the result into the axis's range.
                label: "Enc. offset"
                fieldWidth: 62
                decimals: 1
                suffix: "°"
                value: row.num("encoderOffsetDeg", 0)
                from: -360; to: 360
                onCommitted: function (v) { row.set("encoderOffsetDeg", v) }
            }

            NumberField {
                // Encoder disagreement below this is ignored, so noise and
                // gearbox backlash never move a motor. Floored at ~1.4 steps.
                label: "Deadband"
                fieldWidth: 62
                decimals: 2
                suffix: "°"
                value: row.num("toleranceDeg", 0.5)
                from: 0.05; to: 20
                onCommitted: function (v) { row.set("toleranceDeg", v) }
            }

            NumberField {
                // Only the planner uses this; the sketch reads the real angle
                // from the encoder at power-up.
                label: "Plan start"
                fieldWidth: 62
                suffix: "°"
                value: row.num("homeAngle", 0)
                from: row.num("mechMin", -720)
                to: row.num("mechMax", 720)
                onCommitted: function (v) { row.set("homeAngle", v) }
            }

            Item {
                width: 112
                height: 42

                AppCheckBox {
                    anchors.bottom: parent.bottom
                    anchors.bottomMargin: 2
                    text: "Enc. reversed"
                    accent: row.joint ? row.joint.accent : Theme.accent
                    checked: row.flag("encoderInverted")
                    onToggled: row.set("encoderInverted", checked)
                }
            }

            Item {
                width: 124
                height: 42

                AppCheckBox {
                    anchors.bottom: parent.bottom
                    anchors.bottomMargin: 2
                    text: "Turns full circle"
                    accent: row.joint ? row.joint.accent : Theme.accent
                    checked: row.flag("continuousRotation")
                    onToggled: row.set("continuousRotation", checked)
                }
            }
        }

        // ---- Stepper: hybrid controller tuning --------------------------
        Flow {
            width: parent.width
            spacing: Theme.spacing
            visible: row.stepper

            NumberField {
                // How hard the motor closes a gap to the plan.
                label: "Track gain"
                fieldWidth: 62
                decimals: 1
                suffix: " /s"
                value: row.num("trackingGain", 8)
                from: 0.5; to: 50
                onCommitted: function (v) { row.set("trackingGain", v) }
            }

            NumberField {
                // How fast the encoder pulls the step count back onto the
                // real arm angle. Higher = faster lost-step recovery, more
                // sensitive to encoder noise.
                label: "Enc. gain"
                fieldWidth: 62
                decimals: 2
                suffix: " /s"
                value: row.num("correctionGain", 2)
                from: 0.05; to: 20
                onCommitted: function (v) { row.set("correctionGain", v) }
            }

            NumberField {
                // Cap on that correction, so recovering lost steps is a slide.
                label: "Max corr."
                fieldWidth: 68
                decimals: 1
                suffix: "°/s"
                value: row.num("maxCorrectionDegPerSec", 15)
                from: 0.5; to: 500
                onCommitted: function (v) { row.set("maxCorrectionDegPerSec", v) }
            }

            NumberField {
                label: "Enc. filter"
                fieldWidth: 62
                decimals: 0
                suffix: " ms"
                value: row.num("encoderFilterMs", 15)
                from: 1; to: 500
                onCommitted: function (v) { row.set("encoderFilterMs", v) }
            }
        }

        // ---- Servo: channel, travel and pulse calibration ----------------
        Flow {
            width: parent.width
            spacing: Theme.spacing
            visible: !row.stepper

            NumberField {
                label: "PCA9685 ch."
                fieldWidth: 62
                value: row.num("channel", 0)
                from: 0; to: 15
                warn: row.clash.length > 0
                onCommitted: function (v) { row.set("channel", Math.round(v)) }
            }

            NumberField {
                label: "Limit min"
                fieldWidth: 62
                suffix: "°"
                value: row.num("mechMin", 0)
                from: row.num("nominalMin", 0)
                to: row.num("nominalMax", 180)
                onCommitted: function (v) { row.set("mechMin", v) }
            }

            NumberField {
                label: "Limit max"
                fieldWidth: 62
                suffix: "°"
                value: row.num("mechMax", 180)
                from: row.num("nominalMin", 0)
                to: row.num("nominalMax", 180)
                onCommitted: function (v) { row.set("mechMax", v) }
            }

            NumberField {
                label: "Start angle"
                fieldWidth: 62
                suffix: "°"
                value: row.num("homeAngle", 90)
                from: row.num("mechMin", 0)
                to: row.num("mechMax", 180)
                onCommitted: function (v) { row.set("homeAngle", v) }
            }

            NumberField {
                label: "Pulse min"
                fieldWidth: 68
                suffix: " µs"
                value: row.num("minPulseUs", 500)
                from: 100; to: 3000
                onCommitted: function (v) { row.set("minPulseUs", Math.round(v)) }
            }

            NumberField {
                label: "Pulse max"
                fieldWidth: 68
                suffix: " µs"
                value: row.num("maxPulseUs", 2500)
                from: 100; to: 3000
                onCommitted: function (v) { row.set("maxPulseUs", Math.round(v)) }
            }

            Item {
                width: 96
                height: 42

                AppCheckBox {
                    anchors.bottom: parent.bottom
                    anchors.bottomMargin: 2
                    text: "Mirrored"
                    accent: row.joint ? row.joint.accent : Theme.accent
                    checked: row.flag("inverted")
                    onToggled: row.set("inverted", checked)
                }
            }
        }

        // ---- Gripper: what each named command maps to --------------------
        Row {
            spacing: Theme.spacing
            visible: row.gripper

            Repeater {
                model: row.gripper && row.joint.commands ? row.joint.commands : []

                delegate: Rectangle {
                    required property var modelData

                    width: cmdLabel.implicitWidth + 22
                    height: 22
                    radius: Theme.radiusSmall
                    color: Theme.surfaceHigh
                    border.width: 1
                    border.color: Theme.border

                    Text {
                        id: cmdLabel
                        anchors.centerIn: parent
                        text: parent.modelData.name + " → " + parent.modelData.angle + "°"
                        color: Theme.textSecondary
                        font.family: Theme.fontFamily
                        font.weight: Theme.weightBody
                        font.pixelSize: Theme.fontTiny
                    }
                }
            }
        }
    }
}
